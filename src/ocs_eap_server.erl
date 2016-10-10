%%% ocs_eap_server.erl
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
-module(ocs_eap_server).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_server).

%% export the ocs_eap_server API
-export([]).

%% export the call backs needed for gen_server behaviour
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
			terminate/2, code_change/3]).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").

-record(state,
		{eap_sup :: pid(),
		pwd_sup :: pid(),
		ttls_sup :: pid(),
		socket :: inet:socket(),
		address :: inet:ip_address(),
		port :: non_neg_integer(),
		module :: atom(),
		handlers = gb_trees:empty() :: gb_trees:tree(Key ::
				({NAS :: string() | inet:ip_address(), Port :: string(),
				Peer :: string()}), Value :: (Fsm :: pid()))}).

%%----------------------------------------------------------------------
%%  The ocs_eap_server API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_eap_server gen_server call backs
%%----------------------------------------------------------------------

-spec init(Args :: list()) -> Result :: {ok, State :: #state{}}
		| {ok, State :: #state{}, Timeout :: non_neg_integer() | infinity}
		| {stop, Reason :: term()} | ignore.
%% @doc Initialize the {@module} server.
%% 	Args :: [Sup :: pid(), Module :: atom(), Port :: non_neg_integer(),
%% 	Address :: inet:ip_address()].
%% @see //stdlib/gen_server:init/1
%% @private
%%
init([EapSup, Address, Port]) ->
	process_flag(trap_exit, true),
	{ok, #state{eap_sup = EapSup, address = Address, port = Port}, 0}.

-spec handle_call(Request :: term(), From :: {Pid :: pid(), Tag :: any()},
		State :: #state{}) ->
	Result :: {reply, Reply :: term(), NewState :: #state{}}
		| {reply, Reply :: term(), NewState :: #state{}, Timeout :: non_neg_integer() | infinity}
		| {reply, Reply :: term(), NewState :: #state{}, hibernate}
		| {noreply, NewState :: #state{}}
		| {noreply, NewState :: #state{}, Timeout :: non_neg_integer() | infinity}
		| {noreply, NewState :: #state{}, hibernate}
		| {stop, Reason :: term(), Reply :: term(), NewState :: #state{}}
		| {stop, Reason :: term(), NewState :: #state{}}.
%% @doc Handle a request sent using {@link //stdlib/gen_server:call/2.
%% 	gen_server:call/2,3} or {@link //stdlib/gen_server:multi_call/2.
%% 	gen_server:multi_call/2,3,4}.
%% @see //stdlib/gen_server:handle_call/3
%% @private
handle_call(shutdown, _From, State) ->
	{stop, normal, ok, State};
handle_call(port, _From, #state{port = Port} = State) ->
	{reply, Port, State};
handle_call({request, Address, Port, Secret,
			#radius{code = ?AccessRequest} = Radius}, From, State) ->
	access_request(Address, Port, Secret, Radius, From, State).

-spec handle_cast(Request :: term(), State :: #state{}) ->
	Result :: {noreply, NewState :: #state{}}
		| {noreply, NewState :: #state{}, Timeout :: non_neg_integer() | infinity}
		| {noreply, NewState :: #state{}, hibernate}
		| {stop, Reason :: term(), NewState :: #state{}}.
%% @doc Handle a request sent using {@link //stdlib/gen_server:cast/2.
%% 	gen_server:cast/2} or {@link //stdlib/gen_server:abcast/2.
%% 	gen_server:abcast/2,3}.
%% @see //stdlib/gen_server:handle_cast/2
%% @private
%%
handle_cast(_Request, State) ->
	{noreply, State}.

-spec handle_info(Info :: timeout | term(), State :: #state{}) ->
	Result :: {noreply, NewState :: #state{}}
		| {noreply, NewState :: #state{}, Timeout :: non_neg_integer() | infinity}
		| {noreply, NewState :: #state{}, hibernate}
		| {stop, Reason :: term(), NewState :: #state{}}.
%% @doc Handle a received message.
%% @see //stdlib/gen_server:handle_info/2
%% @private
%%
handle_info(timeout, #state{eap_sup = EapSup} = State) ->
	Children = supervisor:which_children(EapSup),
	{_, PwdSup, _, _} = lists:keyfind(ocs_eap_pwd_fsm_sup, 1, Children),
	{_, TtlsSup, _, _} = lists:keyfind(ocs_eap_ttls_fsm_sup, 1, Children),
	{noreply, State#state{pwd_sup = PwdSup, ttls_sup = TtlsSup}};
handle_info({'EXIT', _Pid, {shutdown, SessionID}},
		#state{handlers = Handlers} = State) ->
	NewHandlers = gb_trees:delete(SessionID, Handlers),
	NewState = State#state{handlers = NewHandlers},
	{noreply, NewState};
handle_info({'EXIT', Fsm, _Reason},
		#state{handlers = Handlers} = State) ->
	Fdel = fun(_F, {Key, Pid, _Iter}) when Pid == Fsm ->
				Key;
			(F, {_Key, _Val, Iter}) ->
				F(F, gb_trees:next(Iter));
			(_F, none) ->
				none
	end,
	Iter = gb_trees:iterator(Handlers),
	case Fdel(Fdel, gb_trees:next(Iter)) of
		none ->
			{noreply, State};
		Key ->
			NewHandlers = gb_trees:delete(Key, Handlers),
			NewState = State#state{handlers = NewHandlers},
			{noreply, NewState}
	end.

-spec terminate(Reason :: normal | shutdown | term(),
		State :: #state{}) -> any().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_server:terminate/3
%% @private
%%
terminate(_Reason, _State) ->
	ok.

-spec code_change(OldVsn :: (Vsn :: term() | {down, Vsn :: term()}),
		State :: #state{}, Extra :: term()) ->
	Result :: {ok, NewState :: #state{}}.
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_server:code_change/3
%% @private
%%
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec access_request(Address :: inet:ip_address(), Port :: pos_integer(),
		Secret :: string(), Radius :: #radius{},
		From :: {Pid :: pid(), Tag :: term()}, State :: #state{}) ->
	{reply, {ok, wait}, NewState :: #state{}}
			| {reply, {error, ignore}, NewState :: #state{}}.
%% @doc Handle a received RADIUS Access Request packet.
%% @private
access_request(Address, Port, Secret,
		#radius{attributes = Attributes} = AccessRequest,
		{RadiusFsm, _Tag} = _From, #state{handlers = Handlers} = State) ->
	try
		NAS = case {radius_attributes:find(?NasIdentifier, Attributes),
				radius_attributes:find(?NasIpAddress, Attributes)} of
			{{ok, NasId}, _} ->
				NasId;
			{{error, not_found}, {ok, NasAddr}} ->
				NasAddr
		end,
		NasPort = case radius_attributes:find(?NasPort, Attributes) of
			{ok, NP} ->
				NP;
			{error, not_found} ->
				radius_attributes:fetch(?NasPortType, Attributes)
		end,
		Peer = radius_attributes:fetch(?CallingStationId, Attributes),
		SessionID = {NAS, NasPort, Peer},
		case gb_trees:lookup(SessionID, Handlers) of
			none ->	
				try
					NewState = start_fsm(AccessRequest, RadiusFsm,
							Address, Port, Secret, SessionID, State),
					{reply, {ok, wait}, NewState}
				catch
					_:_ ->
						{reply, {error, ignore}, State}
				end;
			{value, EapFsm} ->
				gen_fsm:send_event(EapFsm, {AccessRequest, RadiusFsm}),
				{reply, {ok, wait}, State}
		end
	catch
		_:_ ->
			{reply, {error, ignore}, State}
	end.

-spec start_fsm(AccessRequest :: #radius{}, RadiusFsm :: pid(),
		Address :: inet:ip_address(), Port :: integer(),
		Secret :: binary(), SessionID :: tuple(),
		State :: #state{}) -> NewState :: #state{}.
%% @doc Start a new {@link //ocs/ocs_eap_pwd_fsm. ocs_eap_pwd_fsm} session handler.
%% @hidden
start_fsm(AccessRequest, RadiusFsm, Address, Port, Secret, SessionID,
		#state{pwd_sup = Sup, handlers = Handlers} = State) ->
	StartArgs = [Address, Port, Secret, SessionID],
	ChildSpec = [StartArgs, []],
	case supervisor:start_child(Sup, ChildSpec) of
		{ok, EapFsm} ->
			link(EapFsm),
			NewHandlers = gb_trees:insert(SessionID, EapFsm, Handlers),
			gen_fsm:send_event(EapFsm, {AccessRequest, RadiusFsm}),
			State#state{handlers = NewHandlers};
		{error, Reason} ->
			error_logger:error_report(["Error starting EAP session handler",
					{error, Reason}, {supervisor, Sup}, {address, Address},
					{port, Port}, {session, SessionID}]),
			State
	end.

