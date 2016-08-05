%%% ocs_sup.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @docfile "{@docsrc supervision.edoc}"
%%%
-module(ocs_sup).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(supervisor).

%% export the callback needed for supervisor behaviour
-export([init/1]).

%%----------------------------------------------------------------------
%%  The supervisor callback
%%----------------------------------------------------------------------

-spec init(Args :: [term()]) ->
	{ok, {{supervisor:strategy(), non_neg_integer(), pos_integer()},
			[supervisor:child_spec()]}} | ignore.
%% @doc Initialize the {@module} supervisor.
%% @see //stdlib/supervisor:init/1
%% @private
%%
init([AuthPort, AcctPort, RestIp, RestPort] = _Args) ->
	ChildSpecs = [webmachine(RestIp, RestPort),
			server(ocs_server, []),
			supervisor(ocs_radius_sup, [AuthPort, AcctPort])],
	{ok, {{one_for_one, 10, 60}, ChildSpecs}}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec supervisor(StartMod :: atom(), Args :: [term()]) ->
	supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //stdlib/supervisor. supervisor} behaviour.
%% @private
%%
supervisor(StartMod, Args) ->
	StartArgs = [{local, StartMod}, StartMod, Args],
	StartFunc = {supervisor, start_link, StartArgs},
	{StartMod, StartFunc, permanent, infinity, supervisor, [StartMod]}.

-spec server(StartMod :: atom(), Args :: [term()]) ->
	supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //stdlib/gen_server. gen_server} behaviour.
%% @private
%%
server(StartMod, Args) ->
	StartArgs = [StartMod, Args, []],
	StartFunc = {gen_server, start_link, StartArgs},
	{StartMod, StartFunc, permanent, 4000, worker, [StartMod]}.

-spec webmachine(Address :: inet:ip_address(), Port :: integer()) ->
	supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //webmachine/webmachine_mochiweb. webmachine} server.
%% @private
%%
webmachine(Address, Port) ->
	Dispatch = ocs_wm_config:dispatch(),
	WebConfig = [{ip, Address},
					{port, Port},
					{dispatch, Dispatch}],
	StartArgs = [WebConfig],
	StartMod = webmachine_mochiweb,
	StartFunc ={StartMod, start, StartArgs},
	{StartMod, StartFunc, permanent, 4000, worker, [StartMod]}.
