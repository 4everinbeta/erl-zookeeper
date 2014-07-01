%% @author uyounri
%% @doc Tests various substats/subscriber health requirements using Zookeeper.
%%
%%@todo Add description to substats_tests.

-module(substats_tests).

% Public API
-export([
    test_subscriber_health/0
]).

-define(SUB1, 1000).
-define(SUB2, 1000).
-define(INTERVAL1, "1").
-define(INTERVAL2, "2").
-define(INTERVAL3, "3").
-define(SUBSTATS_ROOT, "/substats").

%% ====================================================================
%% API functions
%% ====================================================================
-export([]).

test_subscriber_health() ->
	lager:info("start test"),
	
    % setup
    ez_data:delete(?SUBSTATS_ROOT),
	ez_data:create(?SUBSTATS_ROOT, <<"root">>),
	{ok, _} = ez_data:exists(?SUBSTATS_ROOT),

	%% Create 2 subscribers
    IntervalOneKey = ?SUBSTATS_ROOT ++ "/" ++ ?INTERVAL1,
    IntervalTwoKey = ez_data:chroot_path(?SUBSTATS_ROOT ++ "/", ?INTERVAL2),
    IntervalThreeKey = ez_data:chroot_path(?SUBSTATS_ROOT ++ "/", ?INTERVAL3),
	lager:info("Interval keys: ~p, ~p, ~p", [IntervalOneKey, IntervalTwoKey, IntervalThreeKey]),
	
    {ok, IntervalOneKey} = ez_data:create(IntervalOneKey, <<"test data">>),

    % create/get test
    {ok, _} = ez_data:exists(IntervalOneKey),
    {ok, {<<"test data">>, _}} = ez_data:get(IntervalOneKey),



	%% Start an interval, updating stats for both subscribers, getting stats
	%% Rollover interval, pdate stats in new interval, and get stats
	%% Rollover interval again, remove oldest interval, verify it's not there

	%% Remove all interval data
	ez_data:delete(?SUBSTATS_ROOT ++ "/" ++ ?INTERVAL1),
	ez_data:delete(?SUBSTATS_ROOT).

%% ====================================================================
%% Internal functions
%% ====================================================================


