%%% ocs_radius_disconnect_fsm.erl
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
%%% @reference <a href="http://tools.ietf.org/rfc/rfc3576.txt">
%%% 	RFC3576 - Dynamic Authorization Extensions for RADIUS</a>
%%%
-module(ocs_radius_disconnect_fsm).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the ocs_radius_disconnect_fsm API
-export([]).

%% export the ocs_radius_disconnect_fsm state callbacks
-export([send_request/2, receive_response/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").
-include("ocs.hrl").
-record(statedata,
		{id :: integer(),
		 nas_ip :: inet:ip_address(),
		 nas_id :: undefined | string(),
		 subscriber :: string(),
		 acct_session_id :: string(),
		 secret :: string(),
		 socket :: undefined | inet:socket(),
		 retry_time = 500 :: integer(),
		 retry_count = 0 :: integer(),
		 request :: undefined | binary(),
		 attributes :: radius_attributes:attributes()}).

-define(TIMEOUT, 30000).
-define(ERRORLOG, radius_disconnect_error).

%%----------------------------------------------------------------------
%%  The ocs_radius_disconnect_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_radius_disconnect_fsm gen_fsm call backs
%%----------------------------------------------------------------------

-spec init(Args :: list()) ->
	Result :: {ok, StateName :: atom(), StateData :: #statedata{}}
		| {ok, StateName :: atom(), StateData :: #statedata{},
			Timeout :: non_neg_integer() | infinity}
		| {ok, StateName :: atom(), StateData :: #statedata{}, hibernate}
		| {stop, Reason :: term()} | ignore.
%% @doc Initialize the {@module} finite state machine.
%% @see //stdlib/gen_fsm:init/1
%% @private
%%
init([NasIpAddress, NasIdentifier, Subscriber, AcctSessionId, Secret,
			Attributes, Id]) ->
	process_flag(trap_exit, true),
	StateData = #statedata{nas_ip = NasIpAddress, nas_id = NasIdentifier,
		subscriber = Subscriber, acct_session_id = AcctSessionId,
		secret = Secret, attributes = Attributes, id = Id},
	{ok, send_request, StateData, 0}.

-spec send_request(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>send_request</b> state. This state is responsible
%%		for sending a RADIUS-Disconnect/Request to an access point.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
send_request(timeout, #statedata{nas_ip = NasIpAddress, nas_id = NasIdentifier,
		subscriber = Subscriber, acct_session_id = AcctSessionId, id = Id,
		secret = SharedSecret, attributes = Attributes, retry_time = Retry} = StateData) ->
	{ok, Port} = application:get_env(ocs, radius_disconnect_port),
	Attr0 = radius_attributes:new(),
	Attr1 = radius_attributes:add(?NasIpAddress, NasIpAddress, Attr0),
	Attr2 = radius_attributes:add(?UserName, Subscriber, Attr1),
	Attr3 = radius_attributes:add(?NasPort, Port, Attr2),
	Attr4 = radius_attributes:add(?AcctSessionId, AcctSessionId , Attr3),
	Attr5 = case NasIdentifier of
		undefined ->
			Attr4;
		_ ->
			radius_attributes:add(?NasIdentifier, NasIdentifier, Attr4)
	end,
	Attrs = [?NasPortType, ?NasPortId, ?CallingStationId, ?CalledStationId, ?FramedIpAddress],
	Attr6 = extract_attributes(Attrs, Attributes, Attr5),
	Attributes1 = radius_attributes:codec(Attr6),
	Length = size(Attributes1) + 20,
	RequestAuthenticator = crypto:hash(md5,
			[<<?DisconnectRequest, Id, Length:16>>,
			<<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0>>, Attributes1, SharedSecret]),
	DisconRec = #radius{code = ?DisconnectRequest, id = Id,
			authenticator = RequestAuthenticator, attributes = Attributes1},
	DisconnectRequest = radius:codec(DisconRec),
	case gen_udp:open(0, [{active, once}, binary]) of
		{ok, Socket} ->
			case gen_udp:send(Socket, NasIpAddress, Port, DisconnectRequest)of
				ok ->
					NewStateData = StateData#statedata{id = Id, socket = Socket,
						request = DisconnectRequest},
					{next_state, receive_response, NewStateData, Retry};
				{error, _Reason} ->
					{next_state, send_request, StateData, ?TIMEOUT}
			end;
		{error, _Reason} ->
				{next_state, send_request, StateData, ?TIMEOUT}
	end.

-spec receive_response(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>receive_response</b> state. This state is responsible
%%		for recieving a RADIUS-Disconnect/ACK or RADIUS-Disconnect/NAK from an  access point.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
receive_response(timeout, #statedata{retry_count = Count} = StateData)
		when Count > 5 ->
	{stop, shutdown, StateData};
receive_response(timeout, #statedata{socket = Socket, nas_ip = NasIp ,
		request =  DisconnectRequest, retry_count = Count, retry_time = Retry} = StateData) ->
	{ok, Port} = application:get_env(ocs, radius_disconnect_port),
	NewRetry = Retry * 2,
	NewCount = Count + 1,
	NewStateData = StateData#statedata{retry_count = NewCount, retry_time = NewRetry},
	case gen_udp:send(Socket, NasIp, Port, DisconnectRequest)of
		ok ->
			{next_state, receive_response, NewStateData, NewRetry};
		{error, _Reason} ->
			{next_state, receive_response, NewStateData, 0}
	end.

-spec handle_event(Event :: term(), StateName :: atom(),
		StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
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
		| {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
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
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle a received message.
%% @see //stdlib/gen_fsm:handle_info/3
%% @private
%%
handle_info({udp, _, NasIp, NasPort, Packet}, _StateName, #statedata{id = Id,
		subscriber = Subscriber} = StateData) ->
	case radius:codec(Packet) of
		#radius{code = ?DisconnectAck, id = Id} ->
			F = fun() ->
				case mnesia:read(subscriber, Subscriber, write) of
					[#subscriber{disconnect = false} = Entry] ->
						NewEntry = Entry#subscriber{disconnect = true},
						mnesia:write(subscriber, NewEntry, write);
					[#subscriber{disconnect = true}] ->
						ok
				end
			end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					{stop, shutdown, StateData};
				{aborted, _Reason} ->
					{stop, shutdown, StateData}
			end;
		#radius{code = ?DisconnectNak, id = Id, attributes = Attrbin} ->
			Attr = radius_attributes:codec(Attrbin),
			case radius_attributes:find(?ErrorCause, Attr) of
				{ok, ErrorCause} ->
					error_logger:error_report(["Failed to disconnect subscriber session on",
							{server, NasIp}, {port, NasPort},
							{error, radius_attributes:error_cause(ErrorCause)}]);
				{error, not_found} ->
					{stop, shutdown, StateData}
			end
	end,
	{stop, shutdown, StateData}.

-spec terminate(Reason :: normal | shutdown | term(), StateName :: atom(),
		StateData :: #statedata{}) -> any().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_fsm:terminate/3
%% @private
%%
terminate(_Reason, _StateName, #statedata{socket = undefined} = _StateData) ->
	ok;
terminate(_Reason, _StateName, #statedata{socket = Socket} = _StateData) ->
	gen_udp:close(Socket).

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

-spec extract_attributes(Attributes :: [integer()], 
		AttrList :: radius_attributes:attributes(), CurrentAttrList :: radius_attributes:attributes())->
		NewAttrList :: radius_attributes:attributes().
%% @doc Appends radius attributes needed for a Disconnect/Request
%% @private
%%
extract_attributes([ H | T ] = _Attributes, AttrList, CurrentAttrList) ->
	NewAttrList = case radius_attributes:find(H, AttrList) of
		{error, not_found} ->
			CurrentAttrList;
		{ok, Value}->
			radius_attributes:add(H, Value, CurrentAttrList)
	end,
	extract_attributes(T, AttrList, NewAttrList);
extract_attributes([], _AttrList, CurrentAttrList) ->
	CurrentAttrList.

