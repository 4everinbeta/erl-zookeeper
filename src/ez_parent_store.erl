-module(ez_parent_store).
-compile(export_all).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([insert/1, update/1, delete/1, get/1]).
-include("../include/ez_records.hrl").

%% Public API

start_link() ->
  gen_server:start({local, ?MODULE}, ?MODULE, [], []).

stop(Module) ->
  gen_server:call(Module, stop).

stop() ->
  stop(?MODULE).

state(Module) ->
  gen_server:call(Module, state).

state() ->
  state(?MODULE).

insert(#ez_parent{id=ParentId} = Parent) ->
  gen_server:call(?MODULE, {insert, ParentId, Parent}).
   
update(#ez_parent{id=ParentId} = Parent) ->
  gen_server:call(?MODULE, {update, ParentId, Parent}).
  
delete(#ez_parent{id=ParentId} = _Parent) ->
  gen_server:call(?MODULE, {delete, ParentId}).  

get(#ez_parent{id=ParentId} = _Parent) ->
  ?MODULE:get(ParentId);
get(ParentId) when is_integer(ParentId) ->
  ParentStr = integer_to_list(ParentId),
  ?MODULE:get(ParentStr);
get(ParentId) when is_list(ParentId) ->
  gen_server:call(?MODULE, {get, ParentId}).
 
%% Server implementation, a.k.a.: callbacks

init([]) ->
  {ok, []}.
 
handle_call({insert, ParentId, Parent}, _From, State) ->
  TS = calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time( now()))-719528*24*3600,
  ParentRec = case Parent#ez_parent.date_created == undefined of
                true -> Parent#ez_parent{date_created=TS} ;
                _ -> Parent
        end,
  ParentInsert = term_to_binary(ParentRec),
  ParentKey = lists:flatten(["/", ParentId]),
  {ok, ParentKey} = ez_data:create(ParentKey, ParentInsert),
  {reply, {ok, ParentId}, State};
handle_call({update, ParentId, Parent}, _From, State) ->
  ParentUpdate = term_to_binary(Parent),
  ParentKey = lists:flatten(["/", ParentId]),
  {ok, _} = ez_data:set(ParentKey, ParentUpdate),
  {reply, {ok, ParentId}, State};
handle_call({delete, ParentId}, _From, State) ->
  ParentKey = lists:flatten(["/", ParentId]),
  ez_data:delete(ParentKey),
  {reply, {ok, ParentId}, State};
handle_call({get, ParentId}, _From, State) ->
  ParentKey = lists:flatten(["/", ParentId]),
  ParentData = ez_data:get(ParentKey),
  {reply, {ok, ParentData}, State};
 
handle_call(stop, _From, State) ->
  say("stopping by ~p, state was ~p.", [_From, State]),
  {stop, normal, stopped, State};

handle_call(state, _From, State) ->
  say("~p is asking for the state.", [_From]),
  {reply, State, State};

handle_call(_Request, _From, State) ->
  say("call ~p, ~p, ~p.", [_Request, _From, State]),
  {reply, ok, State}.


handle_cast(_Msg, State) ->
  say("cast ~p, ~p.", [_Msg, State]),
  {noreply, State}.


handle_info(_Info, State) ->
  say("info ~p, ~p.", [_Info, State]),
  {noreply, State}.


terminate(_Reason, _State) ->
  say("terminate ~p, ~p", [_Reason, _State]),
  ok.


code_change(_OldVsn, State, _Extra) ->
  say("code_change ~p, ~p, ~p", [_OldVsn, State, _Extra]),
  {ok, State}.

%% Some helper methods.

say(Format) ->
  say(Format, []).
say(Format, Data) ->
  io:format("~p:~p: ~s~n", [?MODULE, self(), io_lib:format(Format, Data)]).
