-module(ez_data).

-behaviour(gen_server).

% Public API
-export([
    chroot/0,
	chroot_path/2,
    create/2,
    delete/1,
    exists/1,
    add_consumer/1,
    get/1,
    getw/3,
    set/2
]).

% gen_server plumbing
-export([
    code_change/3,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    init/1,
    start_link/3,
    terminate/2
]).

-export([
    selftest/0
]).

-define(MAX_CONNECTION_ATTEMPTS, 10).
-define(RECONNECT_TIMEOUT, 10000). % ms.

-record(state, {
        servers = [],              % zookeeper servers list
        chroot = "",               % chroot for all zookeeper nodes
        zk_connection = undefined, % established zk connection handle
        consumers = []             % the list of consumers (process names or pids) which should be notified about zk connection status changes
    }).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Public API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_link(ZKServers, Chroot, Consumers) ->
    lager:info("[start_link] Starting erl-zookeeper connection manager."),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [ZKServers, Chroot, Consumers], []).

% Provides information about currently configured chroot path.
chroot() ->
    gen_server:call(?MODULE, get_chroot).

% Creates a ZK node `Path` and sets its initial value to `Data`.
create(Path, Data) when is_binary(Data) ->
    gen_server:call(?MODULE, {create, Path, Data}).

% Deletes a ZK node `Path`.
delete(Path) ->
    gen_server:call(?MODULE, {delete, Path}).

% Checks whether a ZK node `Path` exists or not.
exists(Path) ->
    gen_server:call(?MODULE, {exists, Path}).

% Gets the value stored in a ZK node `Path`.
get(Path) ->
    gen_server:call(?MODULE, {get, Path}).

% Gets the value stored in a ZK node `Path` and sets up a ZK watch.
% The watch will notify `FromPid` about modification of the
% ZK node by sending a message {`FromTag`, ZKWatchData}.
getw(Path, FromPid, FromTag) ->
    gen_server:call(?MODULE, {getw, Path, FromPid, FromTag}).

% Sets value of a ZK node `Path` to `Data`.
set(Path, Data) when is_binary(Data) ->
    gen_server:call(?MODULE, {set, Path, Data}).

% Add consumer process to notify about connection status
add_consumer(Pid) ->
    try gen_server:call(?MODULE, {add_consumer, Pid}) of
        _ -> ok
    catch
        _:_ -> lager:warning("add_consumer call failed"),error
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% gen_server callbacks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init([ZKServers, Chroot, Consumers]) ->
    process_flag(trap_exit, true),
    State = #state{servers = ZKServers, chroot = Chroot, consumers = Consumers},
    MaybeConnectedState = reconnect(self(), State),
    {ok, MaybeConnectedState}.

terminate(_Reason, #state{zk_connection = undefined}) -> ok;
terminate(Reason, #state{zk_connection = ZK}) ->
    lager:warning("Terminating. Reason: ~p", [Reason]),
    catch ezk_connection:die(ZK, linked_process_died),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_call(get_chroot, _From, #state{ chroot = Chroot } = State) ->
    {reply, Chroot, State};

handle_call(Request, _From, #state{zk_connection = undefined} = State) ->
    lager:warning("Not connected to ZooKeeper. Request: ~p", [Request]),
    {reply, {error, zk_not_connected}, State};

handle_call({create, Path, Data}, _From, #state{zk_connection = ZK, chroot = Chroot} = State) ->
    FullPath = chroot_path(Chroot, Path),
    ZKResponse = ezk:create(ZK, FullPath, Data),
    lager:info("{create ~p} = ~120p", [{Path, FullPath}, ZKResponse]),
    {reply, ZKResponse, State};

handle_call({delete, Path}, _From, #state{zk_connection = ZK, chroot = Chroot} = State) ->
    FullPath = chroot_path(Chroot, Path),
    ZKResponse = ezk:delete(ZK, FullPath),
    lager:info("[{delete ~p} = ~120p", [{Path, FullPath}, ZKResponse]),
    {reply, ZKResponse, State};

handle_call({exists, Path}, _From, #state{zk_connection = ZK, chroot = Chroot} = State) ->
    FullPath = chroot_path(Chroot, Path),
    ZKResponse = ezk:exists(ZK, FullPath),
    lager:info("{exists ~p} = ~120p", [{Path, FullPath}, ZKResponse]),
    {reply, ZKResponse, State};

handle_call({get, Path}, _From, #state{zk_connection = ZK, chroot = Chroot} = State) ->
    FullPath = chroot_path(Chroot, Path),
    ZKResponse = ezk:get(ZK, FullPath),
    lager:info("{get ~p} = ~120p", [{Path, FullPath}, ZKResponse]),
    {reply, ZKResponse, State};

handle_call({getw, Path, FromPid, FromTag}, _From, #state{zk_connection = ZK, chroot = Chroot} = State) ->
    FullPath = chroot_path(Chroot, Path),
    ZKResponse = ezk:get(ZK, FullPath, FromPid, FromTag),
    lager:info("{getw ~p ~p ~p} = ~120p", [{Path, FullPath}, FromPid, FromTag, ZKResponse]),
    {reply, ZKResponse, State};

handle_call({set, Path, Data}, _From, #state{zk_connection = ZK, chroot = Chroot} = State) ->
    FullPath = chroot_path(Chroot, Path),
    ZKResponse = ezk:set(ZK, FullPath, Data),
    lager:info("{set ~p} = ~p", [{Path, FullPath}, ZKResponse]),
    {reply, ZKResponse, State};

handle_call({add_consumer, Pid}, _From, #state{consumers = OldConsumers} = State) ->
    Exists = lists:member(Pid, OldConsumers),
    if Exists == false ->
            erlang:monitor(process, Pid),
            {noreply, State#state{consumers = [Pid | OldConsumers]}};
        true -> {noreply, State}
    end;

handle_call(Request, _From, State) ->
    lager:warning("Unknown call: ~p", [Request]),
    {reply, {error, unknown_call}, State}.

handle_cast(Request, State) ->
    lager:warning("Unknown cast: ~p", [Request]),
    {noreply, State}.

handle_info(reconnect, #state{zk_connection = undefined } = State) ->
    lager:warning("reconnect. Trying to reconnect..."),
    NewState = reconnect(self(), State),
    {noreply, NewState};

handle_info({'DOWN', _MonRef, process, Pid, _}, State = #state{consumers = OldConsumers}) ->
    {noreply, State#state{consumers = lists:delete(Pid, OldConsumers)}};

handle_info({'EXIT', Pid, Reason}, #state{zk_connection = Pid, consumers = Consumers} = State) ->
    lager:warning("Got EXIT message from a connection stored in the state: ~p; Reason: ~p", [Pid, Reason]),
    lager:warning("Notifying consumers(~p) about ZK connection loss.", [Consumers]),
    notify_consumers(Consumers, down),
    schedule_reconnect(self()),
    {noreply, State#state{zk_connection = undefined}};

handle_info({'EXIT', Pid, Reason}, State) ->
    lager:warning("Got EXIT message from a process not associated with a stored connection: ~p; Reason: ~p", [Pid, Reason]),
    {noreply, State};

handle_info(Info, State) ->
    lager:warning("Unknown info message: ~p", [Info]),
    {noreply, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Internal functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

chroot_path(Chroot, Path) -> Chroot ++ Path.

connect(ZKServers) ->
    lager:info("Connecting to: ~p", [ZKServers]),
    ezk_connection:start_link([ZKServers, ?MAX_CONNECTION_ATTEMPTS]).

schedule_reconnect(Server) ->
    timer:send_after(?RECONNECT_TIMEOUT, Server, reconnect).

reconnect(Server, #state{servers = ZKServers, consumers = Consumers} = State) ->
    case connect(ZKServers) of
        {ok, ZK} ->
            lager:info("Connection established. Notifying consumers(~p) about that.", [Consumers]),
            notify_consumers(Consumers, up),
            State#state{zk_connection = ZK};
        {error, _} ->
            lager:warning("Failed to connect. Schedule a reconnect."),
            schedule_reconnect(Server),
            State
    end.

notify_consumers(Consumers, Status) ->
    lists:foreach(
        fun(Consumer) ->
            lager:info("Notifying ~p about ZK connection status: ~p", [Consumer, Status]),
            try
                Consumer ! {zk_connection, Status}
            catch C:R ->
                lager:warning("Failed to notify ~p about ZK connection status: ~p => ~p:~p", [Consumer, Status, C, R])
            end
        end,
        Consumers).

%%
%% Tests
%%

selftest() ->
    lager:warning("enter"),
    TestKey = "/selftest",
    "/ez/selftest" = chroot_path("/ez", TestKey),
    ChrootedTestKey = chroot_path(chroot(), TestKey),

    % setup
    delete(TestKey),

    % create/get test
    {ok, ChrootedTestKey} = create(TestKey, <<"test data">>),
    {ok, _} = exists(TestKey),
    {ok, {<<"test data">>, _}} = ?MODULE:get(TestKey),

    % set tests
    {ok, _} = set(TestKey, <<"new test data">>),
    {ok, {<<"new test data">>, _}} = ?MODULE:get(TestKey),

    % watches
    {ok, {<<"new test data">>, _}} = getw(TestKey, self(), {watches_test, TestKey}),
    {ok, _} = set(TestKey, <<"newer test data">>),
    receive
        {{watches_test, TestKey}, {ChrootedTestKey, data_changed, 3}} -> 
			lager:info("Received watch for znode <<~p>>", [TestKey]),
			ok
    after 1000 ->
        error(failed_watches_test)
    end,

    % delete test
    {ok, ChrootedTestKey} = delete(TestKey),

    % work with non existing key (since it has already been deleted by the `delete` call above)
    {error, no_dir} = exists(TestKey),
    {error, no_dir} = ?MODULE:get(TestKey),
    {error, no_dir} = set(TestKey, <<"test data">>),
    {error, no_dir} = delete(TestKey),

    ok.
