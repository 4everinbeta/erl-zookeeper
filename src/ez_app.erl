-module(ez_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, start_phase/3]).

-define(APP, ez).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    ez_sup:start_link().

stop(_State) ->
    ok.

start_phase(init, _StartType, _StartArgs) ->
    start_deps().

%%%===================================================================
%%% Internal functions
%%%===================================================================

dep_start(App, Type) ->
    start_ok(App, Type, application:start(App, Type)).

start_ok(_App, _Type, ok) -> ok;
start_ok(_App, _Type, {error, {already_started, _App}}) -> ok;
start_ok(App, Type, {error, {not_started, Dep}}) ->
    ok = dep_start(Dep, Type),
    dep_start(App, Type);
start_ok(App, _Type, {error, Reason}) ->
    erlang:error({app_start_failed, App, Reason}).

start_deps() ->
    application:load(?APP),
    case application:get_key(?APP, deps) of
        {ok, Deps} ->
            [dep_start(App, permanent) || App <- Deps];
        undefined -> ok
    end,
    ok.
