%%% ocs_eap_SUITE.erl
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
%%%  Test suite for the ocs API.
%%%
-module(ocs_eap_SUITE).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

-compile(export_all).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "This suite tests the application's API."}]},
	{timetrap, {minutes, 1}},
	{require, radius_username}, {default_config, radius_username, "ocs"},
	{require, radius_password}, {default_config, radius_password, "ocs123"},
	{require, radius_shared_secret},{default_config, radius_shared_secret, "xyzzy5461"}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before the whole suite.
%%
init_per_suite(Config) ->
	ok = ocs_lib:initialize_db(),
	ok = ocs_lib:start(),
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	SharedSecret = ct:get_config(radius_shared_secret),
	ok = ocs:add_client(AuthAddress, SharedSecret),
	PeerId = "25252525",
	PeerPassword = "ndtcj9fbcwut", %ocs:generate_password(),
	ok = ocs:add_subscriber(PeerId, PeerPassword, <<>>),
	[{peer_id, PeerId} | Config].

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = ocs_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	{ok, IP} = application:get_env(ocs, radius_auth_addr),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, {ip, IP}, binary]),
	[{socket, Socket} | Config].

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, Config) ->
	Socket = ?config(socket, Config),
	ok = 	gen_udp:close(Socket).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() -> 
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() -> 
	[eap_id_request_response, eap_commit_request_response, eap_confirm_request_response,
	unknown_authenticator, invalid_id_response_eap_packet, invalid_id_response_eap_pwd].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------
eap_id_request_response() ->
   [{userdata, [{doc, "Send an EAP-PWD-ID request to peer"}]}].

eap_id_request_response(Config) ->
	Id = 0,
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	{ok, AuthPort} = application:get_env(ocs, radius_auth_port),
	Socket = ?config(socket, Config), 
	UserName = ct:get_config(radius_username),
	SharedSecret = ct:get_config(radius_shared_secret),
	Authenticator = radius:authenticator(),
	AttributeList0 = radius_attributes:new(),
	AttributeList1 = radius_attributes:store(?UserName, UserName, AttributeList0),
	AttributeList2 = radius_attributes:store(?NasPort, 0, AttributeList1),
	AttributeList3 = radius_attributes:store(?NasIdentifier, "tomba", AttributeList2),
	AttributeList4 = radius_attributes:store(?CallingStationId,"de:ad:be:ef:ca:fe", AttributeList3),
	AttributeList5 = radius_attributes:store(?MessageAuthenticator,
		list_to_binary(lists:duplicate(16,0)), AttributeList4),
	Request1 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = AttributeList5},
	RequestPacket1 = radius:codec(Request1),
	MsgAuth = crypto:hmac(md5, SharedSecret, RequestPacket1),
	AttributeList6 = radius_attributes:store(?MessageAuthenticator, MsgAuth, AttributeList5),
	Request2 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = AttributeList6},
	RequestPacket2 = radius:codec(Request2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, RequestPacket2),
	{ok, {_Address, _Port, Packet}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = Id, authenticator = _Authenticator,
		attributes = BinIDReqAttributes} = radius:codec(Packet),
	IDReqAttributes = radius_attributes:codec(BinIDReqAttributes),
	{ok, EAPPacket} = radius_attributes:find(?EAPMessage, IDReqAttributes),
	#eap_packet{code = request, type = ?PWD, identifier = _ID, data = Data} =
		ocs_eap_codec:eap_packet(EAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = id, tot_length = _L,
		data = IDReqBody} = ocs_eap_codec:eap_pwd(Data),
	#eap_pwd_id{group_desc = 19, random_fun = 16#1, prf = 16#1, token =_Token, pwd_prep = none,
		identity = _HostName} = ocs_eap_codec:eap_pwd_id(IDReqBody).

eap_commit_request_response() ->
	[{userdata, [{doc, "Send an EAP-PWD-COMMIT request to peer"}]}].

eap_commit_request_response(Config) ->
	Id = 1,
	PeerID = list_to_binary(?config(peer_id, Config)),
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	{ok, AuthPort} = application:get_env(ocs, radius_auth_port),
	Socket = ?config(socket, Config), 
	UserName = ct:get_config(radius_username),
	SharedSecret = ct:get_config(radius_shared_secret),
	Authenticator = radius:authenticator(),
	IDReqAttributeList0 = radius_attributes:new(),
	IDReqAttributeList1 = radius_attributes:store(?UserName, UserName, IDReqAttributeList0),
	IDReqAttributeList2 = radius_attributes:store(?NasPort, 1, IDReqAttributeList1),
	IDReqAttributeList3 = radius_attributes:store(?NasIdentifier, "tomba1", IDReqAttributeList2),
	IDReqAttributeList4 = radius_attributes:store(?CallingStationId,"de:ad:be:ef:ca:fe",
		IDReqAttributeList3),
	IDReqAttributeList5 = radius_attributes:store(?MessageAuthenticator,
		list_to_binary(lists:duplicate(16,0)), IDReqAttributeList4),
	IDRequest1 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList5},
	IDRequestPacket1 = radius:codec(IDRequest1),
	IDMsgAuth = crypto:hmac(md5, SharedSecret, IDRequestPacket1),
	IDReqAttributeList6 = radius_attributes:store(?MessageAuthenticator, IDMsgAuth, IDReqAttributeList5),
	IDRequest2 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList6},
	IDRequestPacket2 = radius:codec(IDRequest2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDRequestPacket2),
	{ok, {AuthAddress, AuthPort, IdReqPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = Id, authenticator = _IDReqAuthenticator,
		attributes = BinIDReqAttributes} = radius:codec(IdReqPacket),
	IDReqAttributes = radius_attributes:codec(BinIDReqAttributes),
	{ok, IDEAPPacket} = radius_attributes:find(?EAPMessage, IDReqAttributes),
	#eap_packet{code = request, type = ?PWD, identifier = IDEAPId, data = IDData} =
		ocs_eap_codec:eap_packet(IDEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDReqData} = ocs_eap_codec:eap_pwd(IDData),
	#eap_pwd_id{group_desc = 19, random_fun = 16#1, prf = 16#1, token = Token,
		pwd_prep = none, identity = ServerID} = ocs_eap_codec:eap_pwd_id(IDReqData),
	IDRespBody = #eap_pwd_id{token = Token, pwd_prep = none, identity = PeerID},
	IDRespBodyData = ocs_eap_codec:eap_pwd_id(IDRespBody),
	IDRespHeader = #eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDRespBodyData},
	IDEAPData = ocs_eap_codec:eap_pwd(IDRespHeader),
	IDRespPacket = #eap_packet{code = response, type = ?PWD, identifier = IDEAPId, data = IDEAPData},
	IDEAPPacketData = ocs_eap_codec:eap_packet(IDRespPacket),
	IDRespAttributeList1 = radius_attributes:store(?EAPMessage, IDEAPPacketData, IDReqAttributeList5),
	Authenticator2 = radius:authenticator(),
	IDResponse1 = #radius{code = ?AccessRequest, id = 2,  authenticator = Authenticator2,
		attributes = IDRespAttributeList1},
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResponse2 = #radius{code = ?AccessRequest, id = 2, authenticator = Authenticator2,
		attributes = IDRspAttributeList3},
	IDResPacket2 = radius:codec(IDResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDResPacket2),
	{ok, {_Address, _Port, CommitPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = 2, authenticator = _RAuthenticator,
		attributes = CommitReqAttributes} = radius:codec(CommitPacket),
	CommitReqAtt = radius_attributes:codec(CommitReqAttributes),
	{ok, CommitEAPPacket} = radius_attributes:find(?EAPMessage, CommitReqAtt),
	#eap_packet{code = request, type = ?PWD, identifier = EAPId2, data = CommitData} =
		ocs_eap_codec:eap_packet(CommitEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = commit,
		data = CommitReqData} = ocs_eap_codec:eap_pwd(CommitData),
	#eap_pwd_commit{element = _Element_S, scalar = _Scalar_S} = ocs_eap_codec:eap_pwd_commit(CommitReqData),
	P_Rand = crypto:rand_uniform(1, ?R),
	{ok, Password, _Attr} = ocs:find_subscriber(PeerID),
	PWE = ocs_eap_pwd:compute_pwe(Token, PeerID, ServerID, Password),
	{Scalar_P, Element_P} = ocs_eap_pwd:compute_scalar(<<P_Rand:256>>, PWE),
	CommitRespBody = #eap_pwd_commit{scalar = Scalar_P, element = Element_P},
	CommitRespBodyData = ocs_eap_codec:eap_pwd_commit(CommitRespBody),
	CommitRespHeader = #eap_pwd{length = false, more = false, pwd_exch = commit,
		data = CommitRespBodyData},
	CommitEAPData = ocs_eap_codec:eap_pwd(CommitRespHeader),
	CommitRespPacket = #eap_packet{code = response, type = ?PWD, identifier = EAPId2, data = CommitEAPData},
	CommitRespPacketData = ocs_eap_codec:eap_packet(CommitRespPacket),
	CommitAttributeList1 = radius_attributes:store(?EAPMessage,
	   CommitRespPacketData, IDReqAttributeList5),
	Authenticator3 = radius:authenticator(),
	CommitResponse1 = #radius{code = ?AccessRequest, id = 3, authenticator = Authenticator3,
		attributes = CommitAttributeList1},
	CommitReqPacket1 = radius:codec(CommitResponse1),
	CommitRespMsgAuth = crypto:hmac(md5, SharedSecret, CommitReqPacket1),
	CommitAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		CommitRespMsgAuth, CommitAttributeList1),
	CommitResponse2= #radius{code = ?AccessRequest, id = 3, authenticator = Authenticator3,
		attributes = CommitAttributeList3},
	CommitReqPacket2 = radius:codec(CommitResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, CommitReqPacket2),
	{ok, {_Address, _Port, _ConfirmPacket}} = gen_udp:recv(Socket, 0),
	ok =  gen_udp:close(Socket).
	
eap_confirm_request_response() ->
	[{userdata, [{doc, "Send an EAP-PWD-CONFIRM request to peer"}]}].

eap_confirm_request_response(Config) ->
	Id = 1,
	PeerID = list_to_binary(?config(peer_id, Config)),
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	{ok, AuthPort} = application:get_env(ocs, radius_auth_port),
	Socket = ?config(socket, Config),
	UserName = ct:get_config(radius_username),
	SharedSecret = ct:get_config(radius_shared_secret),
	Authenticator = radius:authenticator(),
	IDReqAttributeList0 = radius_attributes:new(),
	IDReqAttributeList1 = radius_attributes:store(?UserName, UserName, IDReqAttributeList0),
	IDReqAttributeList2 = radius_attributes:store(?NasPort, 2, IDReqAttributeList1),
	IDReqAttributeList3 = radius_attributes:store(?NasIdentifier, "tomba2", IDReqAttributeList2),
	IDReqAttributeList4 = radius_attributes:store(?CallingStationId,"de:ad:be:ef:ca:fe",
		IDReqAttributeList3),
	IDReqAttributeList5 = radius_attributes:store(?MessageAuthenticator,
		list_to_binary(lists:duplicate(16,0)), IDReqAttributeList4),
	IDRequest1 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList5},
	IDRequestPacket1 = radius:codec(IDRequest1),
	IDMsgAuth = crypto:hmac(md5, SharedSecret, IDRequestPacket1),
	IDReqAttributeList6 = radius_attributes:store(?MessageAuthenticator, IDMsgAuth, IDReqAttributeList5),
	IDRequest2 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList6},
	IDRequestPacket2 = radius:codec(IDRequest2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDRequestPacket2),
	{ok, {AuthAddress, AuthPort, IdReqPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = Id, authenticator = _IDReqAuthenticator,
		attributes = BinIDReqAttributes} = radius:codec(IdReqPacket),
	IDReqAttributes = radius_attributes:codec(BinIDReqAttributes),
	{ok, IDEAPPacket} = radius_attributes:find(?EAPMessage, IDReqAttributes),
	#eap_packet{code = request, type = ?PWD, identifier = IDEAPId, data = IDData} =
		ocs_eap_codec:eap_packet(IDEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDReqData} = ocs_eap_codec:eap_pwd(IDData),
	#eap_pwd_id{group_desc = 19, random_fun = 16#1, prf = 16#1, token = Token,
		pwd_prep = none, identity = ServerID} = ocs_eap_codec:eap_pwd_id(IDReqData),
	IDRespBody = #eap_pwd_id{token = Token, pwd_prep = none, identity = PeerID},
	IDRespBodyData = ocs_eap_codec:eap_pwd_id(IDRespBody),
	IDRespHeader = #eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDRespBodyData},
	IDEAPData = ocs_eap_codec:eap_pwd(IDRespHeader),
	IDRespPacket = #eap_packet{code = response, type = ?PWD, identifier = IDEAPId, data = IDEAPData},
	IDEAPPacketData = ocs_eap_codec:eap_packet(IDRespPacket),
	IDRespAttributeList1 = radius_attributes:store(?EAPMessage, IDEAPPacketData, IDReqAttributeList5),
	Authenticator2 = radius:authenticator(),
	IDResponse1 = #radius{code = ?AccessRequest, id = 2,  authenticator = Authenticator2,
		attributes = IDRespAttributeList1},
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResponse2 = #radius{code = ?AccessRequest, id = 2, authenticator = Authenticator2,
		attributes = IDRspAttributeList3},
	IDResPacket2 = radius:codec(IDResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDResPacket2),
	{ok, {_Address, _Port, CommitPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = 2, authenticator = _RAuthenticator,
		attributes = CommitReqAttributes} = radius:codec(CommitPacket),
	CommitReqAtt = radius_attributes:codec(CommitReqAttributes),
	{ok, CommitEAPPacket} = radius_attributes:find(?EAPMessage, CommitReqAtt),
	#eap_packet{code = request, type = ?PWD, identifier = EAPId2, data = CommitData} =
		ocs_eap_codec:eap_packet(CommitEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = commit,
		data = CommitReqData} = ocs_eap_codec:eap_pwd(CommitData),
	#eap_pwd_commit{element = Element_S, scalar = Scalar_S} = ocs_eap_codec:eap_pwd_commit(CommitReqData),
	P_Rand = crypto:rand_uniform(1, ?R),
	{ok, Password, _Attr} = ocs:find_subscriber(PeerID),
	PWE = ocs_eap_pwd:compute_pwe(Token, PeerID, ServerID, Password),
	{Scalar_P, Element_P} = ocs_eap_pwd:compute_scalar(<<P_Rand:256>>, PWE),
	CommitRespBody = #eap_pwd_commit{scalar = Scalar_P, element = Element_P},
	CommitRespBodyData = ocs_eap_codec:eap_pwd_commit(CommitRespBody),
	CommitRespHeader = #eap_pwd{length = false, more = false, pwd_exch = commit,
		data = CommitRespBodyData},
	CommitEAPData = ocs_eap_codec:eap_pwd(CommitRespHeader),
	CommitRespPacket = #eap_packet{code = response, type = ?PWD, identifier = EAPId2, data = CommitEAPData},
	CommitRespPacketData = ocs_eap_codec:eap_packet(CommitRespPacket),
	CommitAttributeList1 = radius_attributes:store(?EAPMessage,
	   CommitRespPacketData, IDReqAttributeList5),
	Authenticator3 = radius:authenticator(),
	CommitResponse1 = #radius{code = ?AccessRequest, id = 3, authenticator = Authenticator3,
		attributes = CommitAttributeList1},
	CommitReqPacket1 = radius:codec(CommitResponse1),
	CommitRespMsgAuth = crypto:hmac(md5, SharedSecret, CommitReqPacket1),
	CommitAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		CommitRespMsgAuth, CommitAttributeList1),
	CommitResponse2= #radius{code = ?AccessRequest, id = 3, authenticator = Authenticator3,
		attributes = CommitAttributeList3},
	CommitReqPacket2 = radius:codec(CommitResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, CommitReqPacket2),
	{ok, {_Address, _Port, ConfirmPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = 3, authenticator = _NewAuth,
		attributes = ConfirmReqAttributes} = radius:codec(ConfirmPacket),
	ConfirmReqAtt = radius_attributes:codec(ConfirmReqAttributes),
	{ok, ConfirmEAPPacket} = radius_attributes:find(?EAPMessage, ConfirmReqAtt),
	#eap_packet{code = request, type = ?PWD, identifier = EAPId3, data = ConfirmData} =
		ocs_eap_codec:eap_packet(ConfirmEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = confirm,
		data = Confirm_S} = ocs_eap_codec:eap_pwd(ConfirmData),
	Ciphersuite = <<19:16, 16#1, 16#1>>,
	Kp = ocs_eap_pwd:compute_ks(<<P_Rand:256>>, PWE, Scalar_S, Element_S),
	Input = [Kp, Element_S, Scalar_S, Element_P, Scalar_P, Ciphersuite],
	Confirm_P = ocs_eap_pwd:h(Input),
	ConfirmRespHeader = #eap_pwd{length = false, more = false, pwd_exch = confirm,
		data = Confirm_P},
	ConfirmEAPData = ocs_eap_codec:eap_pwd(ConfirmRespHeader),
	ConfirmRespPacket = #eap_packet{code = response, type = ?PWD, identifier = EAPId3,
		data = ConfirmEAPData},
	ConfirmRespPacketData = ocs_eap_codec:eap_packet(ConfirmRespPacket),
	ConfirmAttributeList1 = radius_attributes:store(?EAPMessage,
	   ConfirmRespPacketData, IDReqAttributeList5),
	Authenticator4 = radius:authenticator(),
	ConfirmResponse1 = #radius{code = ?AccessRequest, id = 4, authenticator = Authenticator4,
		attributes = ConfirmAttributeList1},
	ConfirmReqPacket1 = radius:codec(ConfirmResponse1),
	ConfirmRespMsgAuth = crypto:hmac(md5, SharedSecret, ConfirmReqPacket1),
	ConfirmAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		ConfirmRespMsgAuth, ConfirmAttributeList1),
	ConfirmResponse2= #radius{code = ?AccessRequest, id = 4, authenticator = Authenticator4,
		attributes = ConfirmAttributeList3},
	ConfirmReqPacket2 = radius:codec(ConfirmResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, ConfirmReqPacket2),
	{ok, {_Address, _Port, SuccessPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessAccept, id = 4, authenticator = _NewAuthe,
		attributes = SucReqAttributes} = radius:codec(SuccessPacket),
	SucReqAtt = radius_attributes:codec(SucReqAttributes),
	{ok, SucEAPPacket} = radius_attributes:find(?EAPMessage, SucReqAtt),
	#eap_packet{code = success, identifier = _EAPId, data = <<>>} =
		ocs_eap_codec:eap_packet(SucEAPPacket).

unknown_authenticator() ->
	[{userdata, [{doc, "Unauthorised access request"}]}].

unknown_authenticator(Config) ->
	Id = 4,
	PeerID = list_to_binary(?config(peer_id, Config)),
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	{ok, AuthPort} = application:get_env(ocs, radius_auth_port),
	Socket = ?config(socket, Config),
	UserName = ct:get_config(radius_username),
	SharedSecret = "bogus",
	Authenticator = radius:authenticator(),
	IDReqAttributeList0 = radius_attributes:new(),
	IDReqAttributeList1 = radius_attributes:store(?UserName, UserName, IDReqAttributeList0),
	IDReqAttributeList2 = radius_attributes:store(?NasPort, 3, IDReqAttributeList1),
	IDReqAttributeList3 = radius_attributes:store(?NasIdentifier, "tomba3", IDReqAttributeList2),
	IDReqAttributeList4 = radius_attributes:store(?CallingStationId,"de:ad:be:ef:ca:fe", IDReqAttributeList3),
	IDReqAttributeList5 = radius_attributes:store(?MessageAuthenticator,
		list_to_binary(lists:duplicate(16,0)), IDReqAttributeList4),
	IDRequest1 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList5},
	IDRequestPacket1 = radius:codec(IDRequest1),
	IDMsgAuth = crypto:hmac(md5, SharedSecret, IDRequestPacket1),
	IDReqAttributeList6 = radius_attributes:store(?MessageAuthenticator, IDMsgAuth, IDReqAttributeList5),
	IDRequest2 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList6},
	IDRequestPacket2 = radius:codec(IDRequest2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDRequestPacket2),
	{error, timeout} = gen_udp:recv(Socket, 0, 2000).

invalid_id_response_eap_packet() ->
	[{userdata, [{doc, "Send invalid eap packet"}]}].

invalid_id_response_eap_packet(Config) ->
	Id = 5,
	PeerID = list_to_binary(?config(peer_id, Config)),
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	{ok, AuthPort} = application:get_env(ocs, radius_auth_port),
	Socket = ?config(socket, Config),
	UserName = ct:get_config(radius_username),
	SharedSecret = ct:get_config(radius_shared_secret),
	Authenticator = radius:authenticator(),
	IDReqAttributeList0 = radius_attributes:new(),
	IDReqAttributeList1 = radius_attributes:store(?UserName, UserName, IDReqAttributeList0),
	IDReqAttributeList2 = radius_attributes:store(?NasPort, 5, IDReqAttributeList1),
	IDReqAttributeList3 = radius_attributes:store(?NasIdentifier, "tomba5", IDReqAttributeList2),
	IDReqAttributeList4 = radius_attributes:store(?CallingStationId,"de:ad:be:ef:ca:fe", IDReqAttributeList3),
	IDReqAttributeList5 = radius_attributes:store(?MessageAuthenticator,
		list_to_binary(lists:duplicate(16,0)), IDReqAttributeList4),
	IDRequest1 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList5},
	IDRequestPacket1 = radius:codec(IDRequest1),
	IDMsgAuth = crypto:hmac(md5, SharedSecret, IDRequestPacket1),
	IDReqAttributeList6 = radius_attributes:store(?MessageAuthenticator, IDMsgAuth, IDReqAttributeList5),
	IDRequest2 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList6},
	IDRequestPacket2 = radius:codec(IDRequest2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDRequestPacket2),
	{ok, {AuthAddress, AuthPort, IdReqPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = Id, authenticator = _IDReqAuthenticator,
		attributes = BinIDReqAttributes} = radius:codec(IdReqPacket),
	IDReqAttributes = radius_attributes:codec(BinIDReqAttributes),
	{ok, IDEAPPacket} = radius_attributes:find(?EAPMessage, IDReqAttributes),
	#eap_packet{code = request, type = ?PWD, identifier = IDEAPId, data = IDData} =
		ocs_eap_codec:eap_packet(IDEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDReqData} = ocs_eap_codec:eap_pwd(IDData),
	#eap_pwd_id{group_desc = 19, random_fun = 16#1, prf = 16#1, token = Token,
		pwd_prep = none, identity = _ServerID} = ocs_eap_codec:eap_pwd_id(IDReqData),
	IDRespBody = #eap_pwd_id{token = Token, pwd_prep = none, identity = PeerID},
	IDRespBodyData = ocs_eap_codec:eap_pwd_id(IDRespBody),
	IDRespHeader = #eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDRespBodyData},
	IDEAPData = ocs_eap_codec:eap_pwd(IDRespHeader),

	InvalidEAPPacket = #eap_packet{code = request, type = ?PWD, identifier = IDEAPId, data = IDEAPData},
	IDEAPPacketData = ocs_eap_codec:eap_packet(InvalidEAPPacket),

	IDRespAttributeList1 = radius_attributes:store(?EAPMessage, IDEAPPacketData, IDReqAttributeList5),
	Authenticator2 = radius:authenticator(),
	IDResponse1 = #radius{code = ?AccessRequest, id = 2,  authenticator = Authenticator2,
		attributes = IDRespAttributeList1},
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResponse2 = #radius{code = ?AccessRequest, id = 2, authenticator = Authenticator2,
		attributes = IDRspAttributeList3},
	IDResPacket2 = radius:codec(IDResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDResPacket2),
	{error, timeout} = gen_udp:recv(Socket, 0, 2000).

invalid_id_response_eap_pwd() ->
	[{userdata, [{doc, "Send invalid eap packet data"}]}].

invalid_id_response_eap_pwd(Config) ->
	Id = 6,
	PeerID = list_to_binary(?config(peer_id, Config)),
	{ok, AuthAddress} = application:get_env(ocs, radius_auth_addr),
	{ok, AuthPort} = application:get_env(ocs, radius_auth_port),
	Socket = ?config(socket, Config),
	UserName = ct:get_config(radius_username),
	SharedSecret = ct:get_config(radius_shared_secret),
	Authenticator = radius:authenticator(),
	IDReqAttributeList0 = radius_attributes:new(),
	IDReqAttributeList1 = radius_attributes:store(?UserName, UserName, IDReqAttributeList0),
	IDReqAttributeList2 = radius_attributes:store(?NasPort, 6, IDReqAttributeList1),
	IDReqAttributeList3 = radius_attributes:store(?NasIdentifier, "tomba6", IDReqAttributeList2),
	IDReqAttributeList4 = radius_attributes:store(?CallingStationId,"de:ad:be:ef:ca:fe", IDReqAttributeList3),
	IDReqAttributeList5 = radius_attributes:store(?MessageAuthenticator,
		list_to_binary(lists:duplicate(16,0)), IDReqAttributeList4),
	IDRequest1 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList5},
	IDRequestPacket1 = radius:codec(IDRequest1),
	IDMsgAuth = crypto:hmac(md5, SharedSecret, IDRequestPacket1),
	IDReqAttributeList6 = radius_attributes:store(?MessageAuthenticator, IDMsgAuth, IDReqAttributeList5),
	IDRequest2 = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
		attributes = IDReqAttributeList6},
	IDRequestPacket2 = radius:codec(IDRequest2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDRequestPacket2),
	{ok, {AuthAddress, AuthPort, IdReqPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessChallenge, id = Id, authenticator = _IDReqAuthenticator,
		attributes = BinIDReqAttributes} = radius:codec(IdReqPacket),
	IDReqAttributes = radius_attributes:codec(BinIDReqAttributes),
	{ok, IDEAPPacket} = radius_attributes:find(?EAPMessage, IDReqAttributes),
	#eap_packet{code = request, type = ?PWD, identifier = IDEAPId, data = IDData} =
		ocs_eap_codec:eap_packet(IDEAPPacket),
	#eap_pwd{length = false, more = false, pwd_exch = id,
		data = IDReqData} = ocs_eap_codec:eap_pwd(IDData),
	#eap_pwd_id{group_desc = 19, random_fun = 16#1, prf = 16#1, token = Token,
		pwd_prep = none, identity = _ServerID} = ocs_eap_codec:eap_pwd_id(IDReqData),
	IDRespBody = #eap_pwd_id{token = Token, pwd_prep = none, identity = PeerID},
	IDRespBodyData = ocs_eap_codec:eap_pwd_id(IDRespBody),
	InvalidPWD = #eap_pwd{length = false, more = false, pwd_exch = commit,
		data = IDRespBodyData},
	IDEAPData = ocs_eap_codec:eap_pwd(InvalidPWD),
	IDResEAPPacket = #eap_packet{code = response, type = ?PWD, identifier = IDEAPId, data = IDEAPData},
	IDEAPPacketData = ocs_eap_codec:eap_packet(IDResEAPPacket),
	IDRespAttributeList1 = radius_attributes:store(?EAPMessage, IDEAPPacketData, IDReqAttributeList5),
	Authenticator2 = radius:authenticator(),
	IDResponse1 = #radius{code = ?AccessRequest, id = 2,  authenticator = Authenticator2,
		attributes = IDRespAttributeList1},
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResPacket1 = radius:codec(IDResponse1),
	IDRespMsgAuth = crypto:hmac(md5, SharedSecret, IDResPacket1),
	IDRspAttributeList3 = radius_attributes:store(?MessageAuthenticator,
		IDRespMsgAuth, IDRespAttributeList1),
	IDResponse2 = #radius{code = ?AccessRequest, id = 2, authenticator = Authenticator2,
		attributes = IDRspAttributeList3},
	IDResPacket2 = radius:codec(IDResponse2),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, IDResPacket2),
	{error, timeout} = gen_udp:recv(Socket, 0, 2000).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

