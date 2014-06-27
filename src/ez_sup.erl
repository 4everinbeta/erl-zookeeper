-module(ez_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, reconfigure/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    %%{ok, {{one_for_one, 10, 10}, specs()}}.
   {ok, {{one_for_one, 10, 10}, [{ez_data,{ez_data,start_link,[[{localhost, 2181,30000,10000},
		{ localhost, 2182,30000,10000},
		{ localhost, 2183,30000,10000}],"",[]]},permanent,5000,worker,[ez_data]}]}}.

specs() ->
    case application:get_all_key(ez) of
        {ok, ZK} ->
            [
		        {
			        ez,
			        {
				        ez,
				        start_link,
				        [
					        [{Host, Port, 30000, 10000} || [Host, Port] <- proplists:get_value(hosts, ZK)],
					        proplists:get_value(chroot, ZK),
					        []
				        ]
			        },
			        permanent, 10000, worker, [ez]
		        }
	        ];
        _ -> lager:error("Config is not available, starting empty"),[]
    end.

reconfigure() ->
    superman:reconfigure_supervisor_init_args(?MODULE, []).
