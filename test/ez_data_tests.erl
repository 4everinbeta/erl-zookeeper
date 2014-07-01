-module(ez_data_tests).
-export([test_parent_znode_creation/0, test_child_znode_creation/0,test_parent_child_relationship_creation/0]).

-include("../include/ez_records.erl").

-include_lib("../deps/eunit/include/eunit.hrl").

test_parent_znode_creation() ->
	{ok, ParentId} = create_parent_znode(),
        ParentKey = string:concat("/", ParentId),
        {ok, _} = ez_data:exists(ParentKey),
	{ok, ParentKey} = ez_data:delete(ParentKey),
    	{error, no_dir} = ez_data:exists(ParentKey),
    	{error, no_dir} = ez_data:get(ParentKey),
    	{error, no_dir} = ez_data:set(ParentKey, <<"test data">>),
    	{error, no_dir} = ez_data:delete(ParentKey),	
	ok.


test_child_znode_creation() ->
	%% Insert Parent First
	{ok, ParentId} = create_parent_znode(),
        ParentKey = string:concat("/", ParentId),
        {ok, _} = ez_data:exists(ParentKey),
	%% Insert child
	{ok, ChildId} = create_child_znode(ParentId),
	ChildKey = lists:flatten([ParentKey, "/", ChildId]),
	{ok, _} = ez_data:exists(ChildKey),
	{ok, ChildKey} = ez_data:delete(ChildKey),
    	{error, no_dir} = ez_data:exists(ChildKey),
    	{error, no_dir} = ez_data:get(ChildKey),
    	{error, no_dir} = ez_data:set(ChildKey, <<"test data">>),
    	{error, no_dir} = ez_data:delete(ChildKey),	
	ok.

test_parent_child_relationship_creation() ->
        %% Insert Parent First
        {ok, ParentId} = create_parent_znode(),
        ParentKey = string:concat("/", ParentId),
        {ok, _} = ez_data:exists(ParentKey),
        %% Insert children
        {ok, ChildIds} = create_children(10, ParentId),
	10 = erlang:length(ChildIds),
	VerifResults = verify_children(ParentKey, ChildIds),
	io:format("VerifResults = ~p~n", VerifResults).

verify_children(ParentKey, Children) ->
	verify_children(ParentKey, Children, []).

verify_children(_ParentKey, [], Results) ->
	Results;
verify_children(ParentKey, [Child | Children], Results) ->
	Res = [verify_child(ParentKey, Child) | Results],
	verify_children(ParentKey, Children, Res).

verify_child(ParentKey, ChildId) ->
	try
		ChildKey = lists:flatten([ParentKey, "/", ChildId]),
		{ok, _} = ez_data:exists(ChildKey),
		{ok, ChildKey} = ez_data:delete(ChildKey),
		{error, no_dir} = ez_data:exists(ChildKey),
		{error, no_dir} = ez_data:get(ChildKey),
		{error, no_dir} = ez_data:set(ChildKey, <<"test data">>),
		{error, no_dir} = ez_data:delete(ChildKey),
		ok
	of
		ok -> {ok, ChildId}
	catch
		_ -> {error, ChildId}
	end.

create_parent_znode() ->
	TS = get_timestamp_milliseconds(),
	ParentId = io_lib:format("~p", [TS]),
	ParentRec = #ez_parent{id=ParentId,first_name="Ryan", last_name=lists:flatten(["Brown", io_lib:format("~p", [TS])]), date_created=TS},
	Parent = term_to_binary(ParentRec),
	ParentKey = lists:flatten(["/", ParentRec#ez_parent.id]),
	{ok, ParentKey} = ez_data:create(ParentKey, Parent),
	io:format("~p~n", [ParentKey]),
	{ok, _} = ez_data:exists(ParentKey),
	{ok, ParentId}.

create_child_znode(ParentId) ->
	TS = get_timestamp_milliseconds(),
	%% Insert child
	ChildId = io_lib:format("~p", [TS]),
	ChildRec = #ez_child{id=ChildId, parent_id=ParentId, first_name="Alexander", last_name=lists:flatten(["Brown", ParentId]), date_created=TS},
	Child = term_to_binary(ChildRec),
	ChildKey = lists:flatten(["/", ChildRec#ez_child.parent_id, "/", ChildRec#ez_child.id]),
	{ok, ChildKey} = ez_data:create(ChildKey, Child),
	{ok, _} = ez_data:exists(ChildKey),
	io:format("ChildKey ~p created.~n", [ChildKey]),
	ChildId.

create_children(NumChildren, ParentId) ->
	create_children(NumChildren, ParentId, []).

create_children(NumChildren, _ParentId, Children) when erlang:length(Children) == NumChildren ->
	{ok, Children};
create_children(NumChildren, ParentId, Children) ->
	Ch1 = [create_child_znode(ParentId) | Children],
	create_children(NumChildren, ParentId, Ch1).

get_timestamp_milliseconds() ->
	{Mega, Sec, Micro} = os:timestamp(),
	(Mega*1000000 + Sec)*1000 + round(Micro/1000).
