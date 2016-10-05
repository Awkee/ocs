%%% ocs_eap_pwd_fsm.erl
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
-module(ocs_eap_pwd_fsm).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the ocs_eap_pwd_fsm API
-export([]).

%% export the ocs_eap_pwd_fsm state callbacks
-export([idle/2, wait_for_id/2, wait_for_commit/2, wait_for_confirm/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").
-record(statedata,
		{address :: inet:ip_address(),
		port :: pos_integer(),
		session_id:: {NAS :: inet:ip_address() | string(),
				Port :: string(), Peer :: string()},
		eap_id = 0 :: byte(),
		group_desc  = 19 :: byte(),
		rand_func = 1 :: byte(),
		prf = 1 :: byte(),
		secret :: binary(),
		token :: binary(),
		prep :: none | rfc2759 | saslprep,
		server_id  :: binary(),
		peer_id :: binary(),
		pwe :: binary(),
		s_rand :: integer(),
		scalar_s :: binary(),
		element_s :: binary(),
		scalar_p :: binary(),
		element_p :: binary(),
		ks :: binary(),
		confirm_s :: binary(),
		confirm_p :: binary(),
		mk :: binary(),
		msk :: binary()}).

-define(TIMEOUT, 30000).

%%----------------------------------------------------------------------
%%  The ocs_eap_pwd_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_eap_pwd_fsm gen_fsm call backs
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
init([Address, Port, Secret, SessionID] = _Args) ->
	StateData = #statedata{address = Address, port = Port,
	secret = Secret, session_id = SessionID},
	process_flag(trap_exit, true),
	{ok, idle, StateData, ?TIMEOUT}.

-spec idle(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>idle</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
idle({#radius{code = ?AccessRequest, id = RadiusID,
		authenticator = RequestAuthenticator,
		attributes = Attributes}, RadiusFsm},
		#statedata{eap_id = EapID, session_id = SessionID,
		secret = Secret, group_desc = GroupDesc,
		rand_func = RandFunc, prf = PRF} = StateData) ->
	Token = crypto:rand_bytes(4),
	{ok, HostName} = inet:gethostname(),
	ServerID = list_to_binary(HostName),
	EapPwdId = #eap_pwd_id{group_desc = GroupDesc,
			random_fun = RandFunc, prf = PRF, token = Token,
			pwd_prep = none, identity = ServerID},
	EapPwdData = ocs_eap_codec:eap_pwd_id(EapPwdId),
	EapPwd = #eap_pwd{length = false,
			more = false, pwd_exch = id, data = EapPwdData},
	EapData = ocs_eap_codec:eap_pwd(EapPwd),
	NewStateData = StateData#statedata{token = Token, server_id = ServerID},
	case radius_attributes:find(?EAPMessage, Attributes) of
		{ok, <<>>} ->
			send_response(request, EapID, EapData, ?AccessChallenge,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			{next_state, wait_for_id, NewStateData, ?TIMEOUT};
		{ok, EAPMessage} ->
			case catch ocs_eap_codec:eap_packet(EAPMessage) of
				#eap_packet{code = response, type = ?Identity} ->
					send_response(request, EapID, EapData, ?AccessChallenge,
							RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
					{next_state, wait_for_id, NewStateData, ?TIMEOUT};
				#eap_packet{code = Code, type = EapType, data = Data} ->
					error_logger:warning_report(["Unknown EAP received",
							{pid, self()}, {session_id, SessionID},
							{code, Code}, {type, EapType}, {data, Data}]),
					radius:response(RadiusFsm, {error, ignore}),
					{ok, idle, StateData, ?TIMEOUT};
				{'EXIT', _Reason} ->
					radius:response(RadiusFsm, {error, ignore}),
					{ok, idle, StateData, ?TIMEOUT}
			end;
		{error, not_found} ->
			send_response(request, EapID, EapData, ?AccessChallenge,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			{next_state, wait_for_id, NewStateData, ?TIMEOUT}
	end;
idle({#radius{}, RadiusFsm}, StateData) ->
	radius:response(RadiusFsm, {error, ignore}),
	{ok, idle, StateData, ?TIMEOUT}.

-spec wait_for_id(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>wait_for_id</b> state. This state is responsible
%%		for sending EAP-PWD-ID request to peer.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
wait_for_id(timeout, #statedata{session_id = SessionID} = StateData)->
	{stop, {shutdown, SessionID}, StateData};
wait_for_id({#radius{id = RadiusID, authenticator = RequestAuthenticator,
		attributes = Attributes} = _AccessRequest, RadiusFsm},
		#statedata{token = Token, eap_id = EapID, secret = Secret,
		group_desc = GroupDesc, rand_func = RandFun, prf = PRF,
		server_id = ServerID, session_id = SessionID} = StateData)->
	S_rand = crypto:rand_uniform(1, ?R),
	try
		EAPMessage = radius_attributes:fetch(?EAPMessage, Attributes),
		EapPacket = ocs_eap_codec:eap_packet(EAPMessage),
		#eap_packet{code = response, type = ?PWD, identifier = EapID,
				data = Data} = EapPacket,
		EapHeader = ocs_eap_codec:eap_pwd(Data),
		#eap_pwd{pwd_exch = id, data = BodyData} = EapHeader,
		Body = ocs_eap_codec:eap_pwd_id(BodyData),
		#eap_pwd_id{group_desc = GroupDesc, random_fun = RandFun, prf = PRF,
				 token = Token, pwd_prep = none, identity = PeerID} = Body,
		NewEapID = EapID + 1,
		case catch ocs:find_subscriber(PeerID) of
			{ok, Password, _Attributesi, _Balance} ->
				PWE = ocs_eap_pwd:compute_pwe(Token, PeerID, ServerID, Password),
				{ScalarS, ElementS} = ocs_eap_pwd:compute_scalar(<<S_rand:256>>,
						PWE),
				CommitReq = #eap_pwd_commit{scalar = ScalarS, element = ElementS},
				CommitReqBody = ocs_eap_codec:eap_pwd_commit(CommitReq),
				CommitReqHeader = #eap_pwd{length = false,
					more = false, pwd_exch = commit, data = CommitReqBody},
				CommitEapData = ocs_eap_codec:eap_pwd(CommitReqHeader),
				send_response(request, NewEapID, CommitEapData,
						?AccessChallenge, RadiusID, [], RequestAuthenticator,
						Secret, RadiusFsm),
				NewStateData = StateData#statedata{pwe = PWE, s_rand = S_rand,
					peer_id = PeerID, eap_id = NewEapID, scalar_s = ScalarS,
					element_s = ElementS},
				{next_state, wait_for_commit, NewStateData, ?TIMEOUT};
			error ->
				send_response(failure, EapID, <<>>, ?AccessReject,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
				{stop, {shutdown, SessionID}, StateData}
		end
	catch
		_:_ ->
			radius:response(RadiusFsm, {error, ignore}),
			{next_state, wait_for_id, StateData, ?TIMEOUT}
	end.

-spec wait_for_commit(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>wait_for_commit</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
wait_for_commit(timeout, #statedata{session_id = SessionID} = StateData)->
	{stop, {shutdown, SessionID}, StateData};
wait_for_commit({#radius{attributes = Attributes} = AccessRequest, RadiusFsm},
		#statedata{eap_id = EapID} = StateData) ->
	try 
		EAPMessage = radius_attributes:fetch(?EAPMessage, Attributes),
		EapPacket = ocs_eap_codec:eap_packet(EAPMessage),
		#eap_packet{code = response, type = ?PWD,
				identifier = EapID, data = Data} = EapPacket,
		EapHeader = ocs_eap_codec:eap_pwd(Data),
		#eap_pwd{pwd_exch = commit, data = BodyData} = EapHeader,
		Body = ocs_eap_codec:eap_pwd_commit(BodyData),
		#eap_pwd_commit{element = ElementP, scalar = ScalarP} = Body,
		NewStateData = StateData#statedata{scalar_p = ScalarP,
				element_p = ElementP},
		wait_for_commit1(RadiusFsm, AccessRequest, BodyData, NewStateData)
	catch
		_:_ ->
			radius:response(RadiusFsm, {error, ignore}),
			{next_state, wait_for_commit, StateData, ?TIMEOUT}
	end.
%% @hidden
wait_for_commit1(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = AccessRequest,
		BodyData, #statedata{eap_id = EapID, secret = Secret,
		scalar_s = ScalarS, element_s = ElementS,
		session_id = SessionID} = StateData) ->
	ExpectedSize = size(<<ElementS/binary, ScalarS/binary>>),
	case size(BodyData) of 
		ExpectedSize ->
			wait_for_commit2(RadiusFsm, AccessRequest, StateData);
		_ ->
			send_response(failure, EapID, <<>>, ?AccessReject,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			{stop, {shutdown, SessionID}, StateData}
	end.
%% @hidden
wait_for_commit2(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = AccessRequest,
		#statedata{element_p = ElementP, scalar_p = ScalarP,
		scalar_s = ScalarS, element_s = ElementS, secret = Secret,
		eap_id = EapID, session_id = SessionID} = StateData) ->
	case {ElementP, ScalarP} of
		{ElementS, ScalarS} ->
			send_response(failure, EapID, <<>>, ?AccessReject,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			{stop, {shutdown, SessionID}, StateData};
		_ ->
			wait_for_commit3(RadiusFsm, AccessRequest, StateData)
	end.
%% @hidden
wait_for_commit3(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = AccessRequest,
		#statedata{scalar_p = ScalarP, secret = Secret,
		eap_id = EapID, session_id = SessionID} = StateData)->
	case ScalarP of
		<<ScalarP_Valid:256>> when 1 < ScalarP_Valid, ScalarP_Valid < ?R ->
			wait_for_commit4(RadiusFsm, AccessRequest, StateData);
		_ScalarP_Out_of_Range ->
			send_response(failure, EapID, <<>>, ?AccessReject, RadiusID,
					[], RequestAuthenticator, Secret, RadiusFsm),
			{stop, {shutdown, SessionID}, StateData}
	end.
%% @hidden
wait_for_commit4(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = _AccessRequest,
		#statedata{eap_id = EapID, secret = Secret,
		scalar_p = ScalarP, element_p = ElementP,
		scalar_s = ScalarS, element_s = ElementS,
		s_rand = Srand, pwe = PWE, group_desc = GroupDesc,
		rand_func = RandFunc, prf = PRF} = StateData)->
	case catch ocs_eap_pwd:compute_ks(<<Srand:256>>,
			PWE, ScalarP, ElementP) of
		{'EXIT', _Reason} ->
			radius:response(RadiusFsm, {error, ignore}),
			{next_state, wait_for_commit, StateData, ?TIMEOUT};
		Ks ->
			Ciphersuite = <<GroupDesc:16, RandFunc, PRF>>,
			Input = [Ks, ElementS, ScalarS, ElementP, ScalarP, Ciphersuite],
			ConfirmS = ocs_eap_pwd:h(Input),
			ConfirmHeader = #eap_pwd{length = false,
					more = false, pwd_exch = confirm, data = ConfirmS},
			ConfirmEapData = ocs_eap_codec:eap_pwd(ConfirmHeader),
			NewEapID = EapID + 1,
			send_response(request, NewEapID, ConfirmEapData, ?AccessChallenge,
					RadiusID, [], RequestAuthenticator, Secret, RadiusFsm),
			NewStateData = StateData#statedata{eap_id = NewEapID, ks = Ks,
					confirm_s = ConfirmS},
			{next_state, wait_for_confirm, NewStateData, ?TIMEOUT}
	end.

-spec wait_for_confirm(Event :: timeout | term(), StateData :: #statedata{}) ->
	Result :: {next_state, NextStateName :: atom(), NewStateData :: #statedata{}}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{},
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: #statedata{}, hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: #statedata{}}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>wait_for_confirm</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
wait_for_confirm(timeout, #statedata{session_id = SessionID} = StateData)->
	{stop, {shutdown, SessionID}, StateData};
wait_for_confirm({#radius{attributes = Attributes} = AccessRequest, RadiusFsm},
		#statedata{session_id = SessionID, eap_id = EapID} = StateData)->
	try
		EAPMessage = radius_attributes:fetch(?EAPMessage, Attributes),
		EapData = ocs_eap_codec:eap_packet(EAPMessage),
		#eap_packet{code = response, type = ?PWD,
				identifier = EapID, data = Data} = EapData,
		EapHeader = ocs_eap_codec:eap_pwd(Data),
		#eap_pwd{pwd_exch = confirm, data = ConfirmP} = EapHeader,
		NewEapID = EapID + 1,
		NewStateData = StateData#statedata{confirm_p = ConfirmP,
				eap_id = NewEapID},
		wait_for_confirm1(RadiusFsm, AccessRequest, NewStateData)
	catch
		_:_ ->
			radius:response(RadiusFsm, {error, ignore}),
			{stop, {shutdown, SessionID}, StateData}
	end.
%% @hidden
wait_for_confirm1(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = AccessRequest,
		#statedata{secret = Secret, confirm_s = ConfirmS, eap_id = EapID,
		confirm_p = ConfirmP, session_id = SessionID} = StateData) ->
	ExpectedSize = size(ConfirmS),
	case size(ConfirmP) of 
		ExpectedSize ->
			wait_for_confirm2(RadiusFsm, AccessRequest, StateData);
		_ ->
			send_response(failure, EapID, <<>>, ?AccessReject, RadiusID,
					[], RequestAuthenticator, Secret, RadiusFsm),
			{stop, {shutdown, SessionID}, StateData}
	end.
%% @hidden
wait_for_confirm2(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = AccessRequest,
		#statedata{secret = Secret, eap_id = EapID, ks = Ks,
		confirm_p = ConfirmP, scalar_s = ScalarS, element_s = ElementS,
		scalar_p = ScalarP, element_p = ElementP, group_desc = GroupDesc,
		rand_func = RandFunc, prf = PRF, session_id = SessionID} = StateData) ->
	Ciphersuite = <<GroupDesc:16, RandFunc, PRF>>,
	case ocs_eap_pwd:h([Ks, ElementP, ScalarP,
			ElementS, ScalarS, Ciphersuite]) of
		ConfirmP ->
			wait_for_confirm3(RadiusFsm, AccessRequest, StateData);
		_ ->
			send_response(failure, EapID, <<>>, ?AccessReject, RadiusID,
					[], RequestAuthenticator, Secret, RadiusFsm),
			{stop, {shutdown, SessionID}, StateData}
	end.
%% @hidden
wait_for_confirm3(RadiusFsm, #radius{id = RadiusID,
		authenticator = RequestAuthenticator} = _AccessRequest,
		#statedata{secret = Secret, eap_id = EapID, ks = Ks,
		confirm_p = ConfirmP, confirm_s = ConfirmS, scalar_s = ScalarS,
		scalar_p = ScalarP, group_desc = GroupDesc, rand_func = RandFunc,
		prf = PRF, session_id = SessionID, peer_id = PeerID} = StateData) ->
	Ciphersuite = <<GroupDesc:16, RandFunc, PRF>>,
	MK = ocs_eap_pwd:h([Ks, ConfirmP, ConfirmS]),
	MethodID = ocs_eap_pwd:h([Ciphersuite, ScalarP, ScalarS]),
	<<MSK:64/binary, _EMSK:64/binary>> = ocs_eap_pwd:kdf(MK,
			<<?PWD, MethodID/binary>>, 128),
	Salt = crypto:rand_uniform(16#8000, 16#ffff),
	MsMppeKey = encrypt_key(Secret, RequestAuthenticator, Salt, MSK),
	Attr0 = radius_attributes:new(),
	UserName = binary_to_list(PeerID),
	Attr1 = radius_attributes:store(?UserName, UserName, Attr0),
	VendorSpecific1 = {?Microsoft, {?MsMppeSendKey, {Salt, MsMppeKey}}},
	Attr2 = radius_attributes:add(?VendorSpecific, VendorSpecific1, Attr1),
	VendorSpecific2 = {?Microsoft, {?MsMppeRecvKey, {Salt, MsMppeKey}}},
	Attr3 = radius_attributes:add(?VendorSpecific, VendorSpecific2, Attr2),
	Attr4 = radius_attributes:store(?SessionTimeout, 86400, Attr3),
	Attr5 = radius_attributes:store(?AcctInterimInterval, 3600, Attr4),
	send_response(success, EapID, <<>>, ?AccessAccept,
			RadiusID, Attr5, RequestAuthenticator, Secret, RadiusFsm),
	{stop, {shutdown, SessionID}, StateData#statedata{mk = MK, msk = MSK}}.

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

-spec send_response(EapCode :: request | response | success | failure,
		EapID :: byte(), EapData :: binary(),
		RadiusCode :: integer(), RadiusID :: byte(),
		RadiusAttributes :: radius_attributes:attributes(),
		RequestAuthenticator :: binary() | [byte()], Secret :: binary(),
		RadiusFsm :: pid()) -> ok.
%% @doc Sends an RADIUS-Access/Challenge or Reject or Accept  packet to peer
%% @hidden
send_response(EapCode, EapID, EapData, RadiusCode, RadiusID, RadiusAttributes,
		RequestAuthenticator, Secret, RadiusFsm) ->
	Packet = #eap_packet{code = EapCode, type = ?PWD,
			identifier = EapID, data = EapData},
	EapPacketData = ocs_eap_codec:eap_packet(Packet),
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
	radius:response(RadiusFsm, {response, ResponsePacket}),
	ok.

-spec encrypt_key(Secret :: binary(), RequestAuthenticator :: [byte()],
		Salt :: integer(), Key :: binary()) ->
	Ciphertext :: binary().
%% @doc Encrypt the Pairwise Master Key (PMK) according to RFC2548
%% 	section 2.4.2 for use as String in a MS-MPPE-Send-Key attribute.
%% @private
encrypt_key(Secret, RequestAuthenticator, Salt, Key) when (Salt bsr 15) == 1 ->
	KeyLength = size(Key),
	Plaintext = case (KeyLength + 1) rem 16 of
		0 ->
			<<KeyLength, Key/binary>>;
		N ->
			PadLength = (16 - N) * 8,
			<<KeyLength, Key/binary, 0:PadLength>>
	end,
	F = fun(P, [H | _] = Acc) ->
				B = crypto:hash(md5, [Secret, H]),
				C = crypto:exor(P, B),
				[C | Acc]
	end,
	AccIn = [[RequestAuthenticator, <<Salt:16>>]],
	AccOut = lists:foldl(F, AccIn, [P || <<P:16/binary>> <= Plaintext]),
	iolist_to_binary(tl(lists:reverse(AccOut))).

