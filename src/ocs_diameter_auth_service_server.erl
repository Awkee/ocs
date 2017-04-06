%%% ocs_diameter_auth_service_server.erl
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
%%% @doc This {@link //stdlib/gen_server. gen_server} behaviour callback
%%% 	module receives {@link //diameter. diameter} messages on a port assigned
%%% 	for authentication in the {@link //ocs. ocs} application.
%%%
%%% @reference <a href="https://tools.ietf.org/pdf/rfc6733.pdf">
%%% 	RFC6733 - DIAMETER base protocol</a>
%%%
-module(ocs_diameter_auth_service_server).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_server).

%% export the ocs_diameter_auth_service_server API
-export([]).

%% export the call backs needed for gen_server behaviour
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
			terminate/2, code_change/3]).

-record(state, {}).

-type state() :: #state{}.

-define(AUTHENTICATION, diameter_authentication).

%%----------------------------------------------------------------------
%%  The ocs_diameter_auth_service_server API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_diameter_auth_service_server gen_server call backs
%%----------------------------------------------------------------------

-spec init(Args) -> Result 
	when
		Args :: list(),
		Result :: {ok, State :: state()}
		| {ok, State :: state(), Timeout :: non_neg_integer() | infinity}
		| {stop, Reason :: term()} | ignore.
%% @doc Initialize the {@module} .
%% @see //stdlib/gen_server:init/1
%% @private
%%
init( [Address, Port] = _Args) ->
	SvcName = ?AUTHENTICATION,
	SOptions = service_options(SvcName),
	TOptions = transport_options(diameter_tcp, Address, Port),
	diameter:start_service(SvcName, SOptions),
	diameter:add_transport(SvcName, TOptions),
	{ok, #state{}}.

-spec handle_call(Request, From, State) -> Result
	when
		Request :: term(), 
		From :: {Pid :: pid(), Tag :: any()},
		State :: state(),
		Result :: {reply, Reply :: term(), NewState :: state()}
		| {reply, Reply :: term(), NewState :: state(), Timeout :: non_neg_integer() | infinity}
		| {reply, Reply :: term(), NewState :: state(), hibernate}
		| {noreply, NewState :: state()}
		| {noreply, NewState :: state(), Timeout :: non_neg_integer() | infinity}
		| {noreply, NewState :: state(), hibernate}
		| {stop, Reason :: term(), Reply :: term(), NewState :: state()}
		| {stop, Reason :: term(), NewState :: state()}.
%% @doc Handle a request sent using {@link //stdlib/gen_server:call/2.
%% 	gen_server:call/2,3} or {@link //stdlib/gen_server:multi_call/2.
%% 	gen_server:multi_call/2,3,4}.
%% @see //stdlib/gen_server:handle_call/3
%% @private
handle_call(_Request, _From, State) ->
	{noreply, State}.

-spec handle_cast(Request, State) -> Result
	when
		Request :: term(), 
		State :: state(),
		Result :: {noreply, NewState :: state()}
		| {noreply, NewState :: state(), Timeout :: non_neg_integer() | infinity}
		| {noreply, NewState :: state(), hibernate}
		| {stop, Reason :: term(), NewState :: state()}.
%% @doc Handle a request sent using {@link //stdlib/gen_server:cast/2.
%% 	gen_server:cast/2} or {@link //stdlib/gen_server:abcast/2.
%% 	gen_server:abcast/2,3}.
%% @see //stdlib/gen_server:handle_cast/2
%% @private
%%
handle_cast(_Request, State) ->
	{noreply, State}.

-spec handle_info(Info, State) -> Result
	when
		Info :: timeout | term(), 
		State :: state(),
		Result :: {noreply, NewState :: state()}
		| {noreply, NewState :: state(), Timeout :: non_neg_integer() | infinity}
		| {noreply, NewState :: state(), hibernate}
		| {stop, Reason :: term(), NewState :: state()}.
%% @doc Handle a received message.
%% @see //stdlib/gen_server:handle_info/2
%% @private
%%
handle_info(_Info, State) ->
	{noreply, State}.

-spec terminate(Reason, State) -> any()
	when
		Reason :: normal | shutdown | term(),
      State :: state().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_server:terminate/3
%% @private
%%
terminate(_Reason, _State) ->
	stop.

-spec code_change(OldVsn, State, Extra) -> Result
	when
		OldVsn :: (Vsn :: term() | {down, Vsn :: term()}),
		State :: state(), 
		Extra :: term(),
		Result :: {ok, NewState :: state()}.
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_server:code_change/3
%% @private
%%
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec service_options(Name) -> Options
	when
		Name :: atom(),
		Options :: list().
%% @doc Returns options for a DIAMETER service
%% @hidden
service_options(Name) ->
	[{'Origin-Host', atom_to_list(Name) ++ ".example.com"},
		{'Origin-Realm', "example.com"},{'Vendor-Id', 193},
		{'Product-Name', "Server"}, {'Auth-Application-Id', [0]},
		{restrict_connections, false}, {string_decode, false},
		{application, [{alias, common},
				{dictionary, diameter_gen_base_rfc6733},
				{module, ocs_diameter_auth_service_callback}]}].

-spec transport_options(Transport, Address, Port) -> Options
	when
		Transport :: diameter_tcp | diameter_sctp,
		Address :: inet:ip_address(),
		Port :: inet:port_number(),
		Options :: tuple().
%% @doc Returns options for a DIAMETER transport layer
%% @hidden
transport_options(Transport, Address, Port) ->
	Opts = [{transport_module, Transport},
							{transport_config, [{reuseaddr, true},
							{ip, Address},
							{port, Port}]}],
	{listen, Opts}.

