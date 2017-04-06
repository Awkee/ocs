%%% ocs_diameter_auth_service_fsm.erl
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
%%% @doc This {@link //stdlib/gen_fsm. gen_fsm} behaviour callback
%%% 	module implements functions to subscribe to a {@link //diameter. diameter}
%%% 	service and to react to events sent by {@link //diameter. diameter} service.
%%%
%%% @reference <a href="https://tools.ietf.org/pdf/rfc6733.pdf">
%%% 	RFC6733 - DIAMETER base protocol</a>
%%%
-module(ocs_diameter_auth_service_fsm).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the ocs_diameter_auth_service_fsm API
-export([]).

%% export the ocs_radius_disconnect_fsm state callbacks
-export([wait_for_start/2, started/2, wait_for_stop/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

-include_lib("diameter/include/diameter.hrl").
-record(statedata,
		{transport_ref :: reference()}).

-define(AUTHENTICATION, diameter_authentication).

%%----------------------------------------------------------------------
%%  The ocs_diameter_auth_service_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_diameter_auth_service_fsm gen_fsm call backs
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: list(),
		Result :: {ok, StateName, StateData}
			| {ok, StateName, StateData, Timeout}
			| {ok, StateName, StateData, hibernate}
			| {stop, Reason} | ignore,
		StateName :: atom(),
		StateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: term().
%% @doc Initialize the {@module} finite state machine.
%% @see //stdlib/gen_fsm:init/1
%% @private
%%
init([Address, Port] = _Args) ->
	process_flag(trap_exit, true),
	SvcName = ?AUTHENTICATION,
	SOptions = service_options(SvcName),
	TOptions = transport_options(diameter_tcp, Address, Port),
	diameter:subscribe(SvcName),
	case diameter:start_service(SvcName, SOptions) of
		ok ->
			case diameter:add_transport(SvcName, TOptions) of
				{ok, Ref} ->
					StateData = #statedata{transport_ref = Ref},
					{ok, wait_for_start, StateData, 0};
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end.

-spec wait_for_start(Event, StateData) -> Result
	when
		Event :: timeout | term(), 
		StateData :: #statedata{},
		Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>wait_for_start</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
wait_for_start(timeout, StateData) ->
	{next_state, wait_for_start, StateData}.

-spec started(Event, StateData) -> Result
	when
		Event :: timeout | term(), 
		StateData :: #statedata{},
		Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>started</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
started(timeout, StateData) ->
	{next_state, started, StateData}.

-spec wait_for_stop(Event, StateData) -> Result
	when
		Event :: timeout | term(), 
		StateData :: #statedata{},
		Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>wait_for_stop</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
wait_for_stop(timeout, StateData) ->
	{stop, shutdown, StateData}.

-spec handle_event(Event, StateName, StateData) -> Result
	when
		Event :: term(), 
		StateName :: atom(), 
		StateData :: #statedata{},
		Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason , NewStateData},
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:send_all_state_event/2.
%% 	gen_fsm:send_all_state_event/2}.
%% @see //stdlib/gen_fsm:handle_event/3
%% @private
%%
handle_event(_Event, StateName, StateData) ->
	{next_state, StateName, StateData}.

-spec handle_sync_event(Event, From, StateName, StateData) -> Result
	when
		Event :: term(), 
		From :: {Pid :: pid(), Tag :: term()},
		StateName :: atom(), 
		StateData :: #statedata{},
		Result :: {reply, Reply, NextStateName, NewStateData}
			| {reply, Reply, NextStateName, NewStateData, Timeout}
			| {reply, Reply, NextStateName, NewStateData, hibernate}
			| {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, Reply, NewStateData}
			| {stop, Reason, NewStateData},
		Reply :: term(),
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:sync_send_all_state_event/2.
%% 	gen_fsm:sync_send_all_state_event/2,3}.
%% @see //stdlib/gen_fsm:handle_sync_event/4
%% @private
%%
handle_sync_event(_Event, _From, StateName, StateData) ->
	{reply, ok, StateName, StateData}.

-spec handle_info(Info, StateName, StateData) -> Result
	when
		Info :: term(), 
		StateName :: atom(), 
		StateData :: #statedata{},
		Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle a received message.
%% @see //stdlib/gen_fsm:handle_info/3
%% @private
%%
handle_info(#diameter_event{service = ?AUTHENTICATION, info = EventInfo},
		_StateName, StateData) ->
	change_state(EventInfo, StateData).

-spec terminate(Reason, StateName, StateData) -> any()
	when
		Reason :: normal | shutdown | term(), 
		StateName :: atom(),
		StateData :: #statedata{}.
%% @doc Cleanup and exit.
%% @see //stdlib/gen_fsm:terminate/3
%% @private
%%
terminate(_Reason, _StateName, _StateData) ->
	ok.

-spec code_change(OldVsn, StateName, StateData, Extra) -> Result
	when
		OldVsn :: (Vsn :: term() | {down, Vsn :: term()}),
		StateName :: atom(), 
		StateData :: #statedata{}, 
		Extra :: term(),
		Result :: {ok, NextStateName :: atom(), NewStateData :: #statedata{}}.
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_fsm:code_change/4
%% @private
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
	{ok, StateName, StateData}.

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

-spec change_state(EventInfo, StateData) -> Result
	when
		EventInfo :: term(),
		StateData :: #statedata{},
		Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Chnage the state of the fsm based on the event sent
%% by the diameter service.
%% @hidden
change_state(start, StateData) ->
	{next_state, started, StateData, 0};
change_state({up, _, _, _, _}, StateData) ->
	{next_state, started, StateData, 0};
change_state({up, _, _, __}, StateData) ->
	{next_state, started, StateData, 0};
change_state({down, _, _,  _}, StateData) ->
	{next_state, wait_for_stop, StateData, 0};
change_state({reconnect, _, _}, StateData) ->
	{next_state, started, StateData, 0};
change_state(closed, StateData) ->
	{next_state, started, StateData, 0};
change_state({watchdog, _, _, {_, down}, _}, StateData) ->
	{next_state, wait_for_stop, StateData, 0};
change_state({watchdog, _, _, _, _}, StateData) ->
	{next_state, started, StateData, 0};
change_state(stop, StateData) ->
	{next_state, wait_for_stop, StateData, 0}.

