# erl-zookeeper

A simple erlang application to test reading and writing to zookeeper.

## Note on logging

The included ezk application has very chatty logging. Depending on your preferences, you may
choose to turn the logging down or off entirely.  It is currently turned off, assuming that rebar
doesn't update it. To change it open deps/ezk/src/ezk_log.erl. Near the top of the file you'll see
 ```%%
    %% Determines what kind of messages should be logged.
    %%   0 - nothing
    %%   1 - important things
    %%   2 - even more things
    %%   3 - most things
    %%   4 - also heartbeats
    -define(LEVEL, 0).
```

The logging level is controlled by the **LEVEL** definition.  The original setting is 3.

# Creating and running a release created by rebar

An executable release of this application, including all it's dependencies, can be created using
rebar.  [A general overview of how to use rebar to create releases can be found on the rebar wiki.] (https://github.com/basho/rebar/wiki/Release-handling)  

To create the release ensure you are in the project root directory and run
    rebar compile generate

This will create several directories and new files.

The following files are used by rebar to generate a release.
1. src/ez_app.src
2. rel/reltool.config
3. rebar.config

The following is one of the files created when a release is generated.
1. rel/files/sys.config

## src/ez_app.src

This file needs to contain all the apps needed by erl-zookeeper. Specifically, the {applications, []}
tuple needs to list every required application.  Rebar uses this information to create the release.

## rel/reltool.config

It is very important to get this file correct.  It is created by executing
    rebar create-node nodeid=ez
from within an empty *rel* directory.  This command creates all the basic files used by rebar to 
create the release.  The *nodeid* seems to have to be set to the name of the application in the
src/ez_app.src file.

Since rel/reltool.config has already been created using the above command, this **must** not be 
run again.  Doing so may reset rel/reltool.config to its original state.  That said, the changes
to this file are described next.

The base rel/reltool.config file is heavily modified to account for all the prerequisite applications
(e.g., lager). In particular, the following lines have been changed:
    ...
    {lib_dirs, ["../deps"]}, %% "../deps" is the location of the prerequisite apps
    ...
    %% The following entries were added to the file and must match the {applications, []} tuple 
    %% in src/ez_app.src
    {app, sasl,   [{incl_cond, include}]},
    {app, compiler,   [{incl_cond, include}]},
    {app, syntax_tools,   [{incl_cond, include}]},
    {app, goldrush,   [{incl_cond, include}]},
    {app, lager,   [{incl_cond, include}]},
    {app, ezk,   [{incl_cond, include}]},
    
    %% {lib_dir, ".."} was added to the list and denotes the location of *ez*
    {app, ez, [{mod_cond, app}, {incl_cond, include}, {lib_dir, ".."}]}
    
The remainder of the file is unchanged.

## rel/files/sys.config

This file was added to.  The *sasl* entries are used to configure sasl.  The *lager* entries were
added to customize logging in the application (note: *ezk* uses sasl natively, but *lager*
is a registered sasl event handler and so *ezk* logging is also handled by *lager*).

## rebar.config

The following line was added to the end of the standard rebar.config contents:
    {sub_dirs, ["rel"]}.

# Running erl-zookeeper from the command line

erl-zookeeper can be run from the command line using 
    ./start_in_shell.sh file 
or 
    rel/ez/bin/ez start  

As the name implies, the result of the first approach will be a running erlang shell that can be 
used to interact with the *ez* application.

The second approach uses the capability created by rebar when generating the release.  This command
starts an Erlang node running all the required applications and *ez*.  An Erlang remote shell
can be used to interact with the application by running
    rel/ez/bin/ez attach
    
# Interacting with the application

Inspecting src/ez_data.erl can be used to discover the API for the application.  The simplest way 
to quickly see what the app does is to run
    ez_data:selftest().

This will create, change, watch, verify, and remove data nodes from Zookeeper.

