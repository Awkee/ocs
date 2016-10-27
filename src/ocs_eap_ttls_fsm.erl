%%% ocs_eap_ttls_fsm.erl
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
%%% @reference <a href="http://tools.ietf.org/rfc/rfc3579.txt">
%%% 	RFC3579 - RADIUS Support For EAP</a>
%%%
-module(ocs_eap_ttls_fsm).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the ocs_eap_ttls_fsm API
-export([]).

%% export the ocs_eap_ttls_fsm state callbacks
-export([eap_start/2, ttls/2, aaa/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").

-record(statedata,
		{address :: inet:ip_address(),
		port :: pos_integer(),
		session_id :: {NAS :: inet:ip_address() | string(),
			Port :: string(), Peer :: string()},
		secret :: binary(),
		eap_id = 0 :: byte(),
		start :: #radius{},
		server_id :: binary(),
		radius_fsm :: pid(),
		radius_id :: byte(),
		req_auth :: [byte()],
		ssl_pid :: pid()}).

-define(TIMEOUT, 30000).

%%----------------------------------------------------------------------
%%  The ocs_eap_ttls_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_eap_ttls_fsm gen_fsm call backs
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
init([Address, Port, RadiusFsm, Secret, SessionID, AccessRequest] = _Args) ->
	{ok, _TLSkey} = application:get_env(ocs, tls_key),
	{ok, _TLScert} = application:get_env(ocs, tls_crt),
	{ok, _TLSport} = application:get_env(ocs, tls_port),
	{ok, Hostname} = inet:gethostname(),
	StateData = #statedata{address = Address, port = Port,
			radius_fsm = RadiusFsm, secret = Secret, session_id = SessionID,
			server_id = list_to_binary(Hostname), start = AccessRequest},
	process_flag(trap_exit, true),
	{ok, eap_start, StateData, 0}.

-spec eap_start(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>eap_start</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
eap_start(timeout, #statedata{start = #radius{code = ?AccessRequest,
		id = RadiusID, authenticator = RequestAuthenticator,
		attributes = Attributes}, radius_fsm = RadiusFsm,
		eap_id = EapID, session_id = SessionID,
		secret = Secret} = StateData) ->
	{ok, SslSocket1} = ssl:listen(self(), []),
	{ok, SslSocket2} = ssl:transport_accept(SslSocket1),
	EapTtls = #eap_ttls{start = true},
	EapData = ocs_eap_codec:eap_ttls(EapTtls),
	case radius_attributes:find(?EAPMessage, Attributes) of
		{ok, <<>>} ->
			EapPacket = #eap_packet{code = request, type = ?TTLS,
					identifier = EapID, data = EapData},
			send_response(EapPacket, ?AccessChallenge,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			ssl:ssl_accept(SslSocket2),
			{next_state, ttls, StateData, ?TIMEOUT};
		{ok, EAPMessage} ->
			case catch ocs_eap_codec:eap_packet(EAPMessage) of
				#eap_packet{code = response,
						type = ?Identity, identifier = StartEapID} ->
					NewEapID = StartEapID + 1,
					NewEapPacket = #eap_packet{code = request, type = ?TTLS,
							identifier = NewEapID, data = EapData},
					send_response(NewEapPacket, ?AccessChallenge,
							RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
					ssl:ssl_accept(SslSocket2),
					NewStateData = StateData#statedata{eap_id = NewEapID},
					{next_state, ttls, NewStateData, ?TIMEOUT};
				#eap_packet{code = request, identifier = NewEapID} ->
					NewEapPacket = #eap_packet{code = response, type = ?LegacyNak,
							identifier = NewEapID, data = <<0>>},
					send_response(NewEapPacket, ?AccessReject,
							RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
					{stop, {shutdown, SessionID}, StateData};
				#eap_packet{code = Code,
							type = EapType, identifier = NewEapID, data = Data} ->
					error_logger:warning_report(["Unknown EAP received",
							{pid, self()}, {session_id, SessionID},
							{eap_id, NewEapID}, {code, Code},
							{type, EapType}, {data, Data}]),
					NewEapPacket = #eap_packet{code = failure, identifier = NewEapID},
					send_response(NewEapPacket, ?AccessReject,
							RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
					{stop, {shutdown, SessionID}, StateData};
				{'EXIT', _Reason} ->
					NewEapPacket = #eap_packet{code = failure, identifier = EapID},
					send_response(NewEapPacket, ?AccessReject,
							RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
					{stop, {shutdown, SessionID}, StateData}
			end;
		{error, not_found} ->
			EapPacket = #eap_packet{code = request, type = ?TTLS,
					identifier = EapID, data = EapData},
			send_response(EapPacket, ?AccessChallenge,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			ssl:ssl_accept(SslSocket2),
			{next_state, ttls, StateData, ?TIMEOUT}
	end.

-spec ttls(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>ttls</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
ttls(timeout, #statedata{session_id = SessionID} = StateData) ->
	{stop, {shutdown, SessionID}, StateData};
ttls({ssl_pid, SslPid}, StateData) ->
	{next_state, ttls, StateData#statedata{ssl_pid = SslPid}, ?TIMEOUT};
ttls({#radius{code = ?AccessRequest, id = RadiusID,
		authenticator = RequestAuthenticator, attributes = Attributes},
		RadiusFsm}, #statedata{secret = Secret, eap_id = EapID,
		session_id = SessionID, ssl_pid = SslPid} = StateData) ->
	EapMessages = radius_attributes:get_all(?EAPMessage, Attributes),
	NewStateData = StateData#statedata{radius_fsm = RadiusFsm,
			radius_id = RadiusID, req_auth = RequestAuthenticator},
	ttls1(EapMessages, undefined, [], NewStateData).
%% @hidden
ttls1([H | T], Length, Acc, #statedata{radius_fsm = RadiusFsm,
		radius_id = RadiusID, req_auth = RequestAuthenticator,
		session_id = SessionID, secret = Secret, eap_id = EapID,
		ssl_pid = SslPid} = StateData) ->
	try
		#eap_packet{code = response, type = ?TTLS, identifier = EapID,
				data = TtlsData} = ocs_eap_codec:eap_packet(H),
		case ocs_eap_codec:eap_ttls(TtlsData) of
			#eap_ttls{message_len = NewLength, more = true,
					data = Data} when is_integer(Length) ->
				ttls1(T, NewLength, [Data | Acc], StateData);
			#eap_ttls{more = true, data = Data} ->
				ttls1(T, Length, [Data | Acc], StateData);
			#eap_ttls{more = false, data = Data} ->
				NewData = iolist_to_binary(lists:reverse([Data | Acc])),
				case Length of
					undefined ->
						ok;
					Length when size(NewData) /= Length ->
						throw(bad_message_length)
				end,
				ocs_eap_ttls_transport:deliver(SslPid, self(), NewData),
				case T of
					[] ->
						ok;
					T ->
						error_logger:error_report(["Extra EAP-Message attributes",
								{session_id, SessionID}, {attributes, T}])
				end,
				{next_state, aaa, StateData, ?TIMEOUT}
		end
	catch
		_:_ ->
			EapPacket = #eap_packet{code = failure, identifier = EapID},
			send_response(EapPacket, ?AccessReject,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			{stop, {shutdown, SessionID}, StateData}
	end;
ttls1([], Length, Acc, #statedata{radius_fsm = RadiusFsm,
		radius_id = RadiusID, req_auth = RequestAuthenticator,
		session_id = SessionID, secret = Secret, eap_id = EapID} = StateData) ->
	EapPacket = #eap_packet{code = failure, identifier = EapID},
	send_response(EapPacket, ?AccessReject,
			RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
	{stop, {shutdown, SessionID}, StateData}.

-spec aaa(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>aaa</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @todo EAP-TTLS fragmentation
%% @private
aaa(timeout, #statedata{session_id = SessionID} = StateData) ->
	{stop, {shutdown, SessionID}, StateData};
aaa({ssl_pid, SslPid}, StateData) ->
	{next_state, aaa, StateData#statedata{ssl_pid = SslPid}, ?TIMEOUT};
aaa({eap_ttls, SslPid, Data}, #statedata{ssl_pid = SslPid,
		radius_fsm = RadiusFsm, radius_id = RadiusID,
		req_auth = RequestAuthenticator, secret = Secret,
		eap_id = EapID} = StateData) when size(Data) =< 65529 ->
	EapTtls = #eap_ttls{data = Data},
	EapData = ocs_eap_codec:eap_ttls(EapTtls),
	EapPacket = #eap_packet{code = request, type = ?TTLS,
			identifier = EapID, data = EapData},
	send_response(EapPacket, ?AccessChallenge,
			RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
	{next_state, ttls, StateData, ?TIMEOUT}.
%aaa({eap_ttls, SslPid,
%		<<Chunk:65529/binary, Rest/binary>> = Data, StateData) ->

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
	{next_state, StateName, StateData, ?TIMEOUT}.

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
handle_info(_Info, StateName, StateData) ->
	{next_state, StateName, StateData, ?TIMEOUT}.

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

-spec send_response(EapPacket :: #eap_packet{},
		RadiusCode :: integer(), RadiusID :: byte(),
		RadiusAttributes :: radius_attributes:attributes(),
		RequestAuthenticator :: binary() | [byte()], Secret :: binary(),
		RadiusFsm :: pid()) -> ok.
%% @doc Sends an RADIUS-Access/Challenge or Reject or Accept  packet to peer
%% @hidden
send_response(EapPacket, RadiusCode, RadiusID, RadiusAttributes,
		RequestAuthenticator, Secret, RadiusFsm) when size(EapPacket) =< 247 ->
	EapPacketData = ocs_eap_codec:eap_packet(EapPacket),
	AttrList1 = radius_attributes:store(?EAPMessage, EapPacketData,
			RadiusAttributes),
	AttrList2 = radius_attributes:store(?MessageAuthenticator,
		<<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0>>, AttrList1),
	Attributes1 = radius_attributes:codec(AttrList2),
	Length = size(Attributes1) + 20,
	MessageAuthenticator = crypto:hmac(md5, Secret, [<<RadiusCode, RadiusID,
			Length:16>>, RequestAuthenticator, Attributes1]),
	AttrList3 = radius_attributes:store(?MessageAuthenticator,
			MessageAuthenticator, AttrList2),
	Attributes2 = radius_attributes:codec(AttrList3),
	ResponseAuthenticator = crypto:hash(md5, [<<RadiusCode, RadiusID,
			Length:16>>, RequestAuthenticator, Attributes2, Secret]),
	Response = #radius{code = RadiusCode, id = RadiusID,
			authenticator = ResponseAuthenticator, attributes = Attributes2},
	ResponsePacket = radius:codec(Response),
	radius:response(RadiusFsm, {response, ResponsePacket}).

