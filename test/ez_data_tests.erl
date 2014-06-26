-module(ez_data_tests).
-compile(export_all).

-include("/Users/browrk/workspace/erlang/erl-zookeeper/include/ez_records.erl").

-include_lib("eunit/include/eunit.hrl").

create_parent_znode() ->
	TS = calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time( now()))-719528*24*3600,
	Parent = #ez_parent{id="12345",first_name="Ryan", last_name"Brown", date_created=TS},
	 