%%% ocs_eap_fsm.erl
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
-module(ocs_eap_fsm).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the radius_fsm API
-export([]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

%% export the gen_fsm state call backs
-export([idle/2]).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").

-record(statedata,
		{socket :: inet:socket(),
		module :: atom(),
		address :: inet:ip_address(),
		port :: pos_integer(),
		identifier :: non_neg_integer(),
		authenticator :: binary(),
		response :: ignore | undefined | term()}).

-define(WAITSTART,   4000).
-define(WAITRETRIES, 8000).

%%----------------------------------------------------------------------
%%  The radius_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The radius_fsm gen_fsm call backs
%%----------------------------------------------------------------------

-spec init(Args :: list()) ->
	Result :: {ok, StateName :: atom(), StateData :: #statedata{}}
		| {ok, StateName :: atom(), StateData :: #statedata{},
			Timeout :: non_neg_integer() | infinity}
		| {ok, StateName :: atom(), StateData :: #statedata{}, hibernate}
		| {stop, Reason :: term()} | ignore.
%% @doc Initialize the {@module} finite state machine.
%% 	Args :: [Socket :: socket(), Module :: atom(),
%% 	Address :: inet:ip_address(), Port :: non_neg_integer(),
%% 	Identifier = non_neg_integer()].
%% @see //stdlib/gen_fsm:init/1
%% @private
%%
init([Socket, Module, Address, Port, Identifier] = _Args) ->
	process_flag(trap_exit, true),
	StateData = #statedata{socket = Socket, module = Module,
			address = Address, port = Port, identifier = Identifier},
	{ok, idle, StateData, ?WAITSTART}.

-spec idle(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%% 	gen_fsm:send_event/2} in the <b>idle</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
idle(<<_Code, Identifier, Authenticator:168/binary, _/binary>> = _Event,
		#statedata{identifier = Identifier, authenticator = Authenticator,
				response = ignore} = StateData) ->
		{next_state, idle, StateData, ?WAITRETRIES};
idle(<<_Code, Identifier, Authenticator:16/binary, _/binary>> = Event,
		#statedata{identifier = Identifier, authenticator = CachedAuthenticator,
		socket = Socket, module = Module, address = Address,
		port = Port} = StateData) when Authenticator /= CachedAuthenticator ->
	case Module:request(Address, Port, Event) of
		{error, ignore} ->
			NewStateData = StateData#statedata{authenticator = Authenticator,
					response = ignore},
			{next_state, idle, NewStateData, ?WAITRETRIES};
		{error, Reason} ->
			NewStateData = StateData#statedata{authenticator = Authenticator},
			{stop, Reason, NewStateData};
		RadiusResponse ->
			NewStateData = StateData#statedata{authenticator = Authenticator,
					response = RadiusResponse},
			case gen_udp:send(Socket, Address, Port, RadiusResponse) of
				ok ->
					{next_state, idle, NewStateData, ?WAITRETRIES};
				{error, Reason} ->
					{stop, Reason, NewStateData}
			end
	end;
idle(<<_Code, Identifier, Authenticator:16/binary, _/binary>> = _Event,
		#statedata{identifier = Identifier, authenticator = Authenticator,
				response = Response, socket = Socket,
				address = Address, port = Port} = StateData) ->
	case gen_udp:send(Socket, Address, Port, Response) of
		ok ->
			{next_state, idle, StateData, ?WAITRETRIES};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
idle(timeout, #statedata{address = Address, port = Port,
		identifier = Identifier} = StateData) ->
	Id = {Address, Port, Identifier},
	{stop, {shutdown, Id}, StateData}.

-spec handle_event(Event :: term(), StateName :: atom(),
		StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:send_all_state_event/2.
%% 	gen_fsm:send_all_state_event/2}.
%% @see //stdlib/gen_fsm:handle_event/3
%% @private
%%
handle_event(_Event, StateName, StateData) ->
	{next_state, StateName, StateData}.

-spec handle_sync_event(Event :: term(), From :: {Pid :: pid(), Tag :: term()},
		StateName :: atom(), StateData :: #statedata{}) ->
	Result :: {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: #statedata{}}
		| {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: #statedata{}, Timeout :: non_neg_integer() | infinity}
		| {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), Reply :: term(), NewStateData :: #statedata{}}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:sync_send_all_state_event/2.
%% 	gen_fsm:sync_send_all_state_event/2,3}.
%% @see //stdlib/gen_fsm:handle_sync_event/4
%% @private
%%
handle_sync_event(_Event, _From, StateName, StateData) ->
	{reply, ok, StateName, StateData}.

-spec handle_info(Info :: term(), StateName :: atom(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle a received message.
%% @see //stdlib/gen_fsm:handle_info/3
%% @private
%%
handle_info(_Info, StateName, StateData) ->
	{next_state, StateName, StateData}.

-spec terminate(Reason :: normal | shutdown | term(), StateName :: atom(),
		StateData :: #statedata{}) -> any().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_fsm:terminate/3
%% @private
%%
terminate(_Reason, _StateName, _StateData) ->
	ok.

-spec code_change(OldVsn :: (Vsn :: term() | {down, Vsn :: term()}),
		StateName :: atom(), StateData :: #statedata{}, Extra :: term()) ->
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

