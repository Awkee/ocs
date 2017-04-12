%%% ocs_diameter_auth_SUITE.erl
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
%%%  @doc Test suite for authentication with DIAMETER protocol in
%%%  {@link //ocs. ocs}
%%%
-module(ocs_diameter_auth_SUITE).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "Test suite for authentication with DIAMETER protocol in OCS"}]},
	{timetrap, {seconds, 8}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	ok = ocs_test_lib:initialize_db(),
	ok = ocs_test_lib:start(),
	{ok, [{auth, AuthInstance}, {acct, _AcctInstance}]} = application:get_env(ocs, diameter),
	[{Address, Port, _}] = AuthInstance,
	SvcName = diameter_base_app_client,
	true = diameter:subscribe(SvcName),
	ok = diameter:start_service(SvcName, service_opts(SvcName)),
	{ok, Ref} = connect(SvcName, Address, Port, diameter_tcp),
	receive
		#diameter_event{service = SvcName, info = start} ->
			[{svc_name, SvcName}] ++ Config;
		_ ->
			{skip, diameter_service_not_started}
	end.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	SvcName = ?config(svc_name, Config),
	ok = diameter:stop_service(SvcName),
	ok = ocs_test_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	Config.

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, _Config) ->
	ok.

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[capability_exchange].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------
capability_exchange() ->
	[{userdata, [{doc, "CER/CEA message exchange between DIAMETER client and server"}]}].

capability_exchange(_Config) ->
	SvcName = diameter_base_app_client,
	{ok, [{auth, AuthInstance}, {acct, _AcctInstance}]} = application:get_env(ocs, diameter),
	[{Address, Port, _}] = AuthInstance,
	proc_lib:spawn_link(diameter_test_client, start, [self(), SvcName, Address, Port]),
	diameter_client_response().

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

diameter_client_response() ->
	receive
		started ->
			test_case_started;
		stopped ->
			test_case_stopped
	end.

