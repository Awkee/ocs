%%% ocs_diameter_auth_port_server.erl
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
-module(ocs_diameter_auth_port_server).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(gen_server).

%% export the ocs_diameter_auth_port_server API
-export([]).

%% export the call backs needed for gen_server behaviour
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
			terminate/2, code_change/3]).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("../include/diameter_gen_nas_application_rfc7155.hrl").
-include("ocs.hrl").

-record(state,
		{auth_port_sup :: pid(),
		simple_auth_sup :: undefined | pid(),
		handlers = gb_trees:empty() :: gb_trees:tree(
				Key :: (SessionId :: string()), Value :: (Fsm :: pid()))}).

-type state() :: #state{}.
-type capabilities() :: #diameter_caps{}.

%%----------------------------------------------------------------------
%%  The ocs_diameter_auth_port_server API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_diameter_auth_port_server gen_server call backs
%%----------------------------------------------------------------------

-spec init(Args) -> Result 
	when
		Args :: list(),
		Result :: {ok, State :: state()}
		| {ok, State :: state(), Timeout :: non_neg_integer() | infinity}
		| {stop, Reason :: term()} | ignore.
%% @doc Initialize the {@module} server.
%% 	Args :: [Sup :: pid(), Module :: atom(), Port :: non_neg_integer(),
%% 	Address :: inet:ip_address()].
%% @see //stdlib/gen_server:init/1
%% @private
%%
init([AuthPortSup, _Address, _Port, _Options]) ->
	process_flag(trap_exit, true),
	State = #state{auth_port_sup = AuthPortSup},
	{ok, State, 0}.

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
handle_call({diameter_request, Caps, Request}, _From, State) ->
	request(Caps, Request, State).

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
handle_info(timeout, #state{auth_port_sup = AuthPortSup} = State) ->
	Children = supervisor:which_children(AuthPortSup),
	{_, SimpleAuthSup, _, _} = lists:keyfind(ocs_simple_auth_fsm_sup, 1, Children),
	NewState = State#state{simple_auth_sup = SimpleAuthSup},
	{noreply, NewState};
handle_info({'EXIT', Fsm, {shutdown, SessionId}},
		#state{handlers = Handlers} = State) ->
	case gb_trees:lookup(SessionId, Handlers) of
		{value, Fsm} ->
			NewHandlers = gb_trees:delete(SessionId, Handlers),
			{noreply, State#state{handlers = NewHandlers}};
		none ->
			{noreply, State}
	end;
handle_info({'EXIT', Fsm, _Reason},
		#state{handlers = Handlers} = State) ->
	Fdel = fun(_F, {Key, {Pid, _Identity}, _Iter}) when Pid == Fsm ->
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

-spec request(Caps, Request, State) -> Reply
	when
		Caps :: capabilities(),
		Request :: #diameter_nas_app_AAR{} | #diameter_nas_app_STR{},
		State :: state(),
		Reply :: {reply, Answer, State},
		Answer :: #diameter_nas_app_AAA{} | #diameter_nas_app_STA{}.
%% @doc Based on the DIAMETER request generate appropriate DIAMETER
%% answer.
%% @hidden
request(Caps, Request, State) when is_record(Request, diameter_nas_app_AAR) ->
	#diameter_caps{origin_host = {OHost,_}, origin_realm = {ORealm,_}} = Caps,
	request1(OHost, ORealm, Request, State);
request(Caps, Request, State) when is_record(Request, diameter_nas_app_STR) ->
	#diameter_caps{origin_host = {OHost,_}, origin_realm = {ORealm,_}} = Caps,
	SessionId = Request#diameter_nas_app_STR.'Session-Id',
	try
		Username = Request#diameter_nas_app_STR.'User-Name',
		F = fun() ->
			case mnesia:read(subscriber, Username, write) of
				[#subscriber{disconnect = false} = Entry] ->
					NewEntry = Entry#subscriber{disconnect = true},
					mnesia:write(subscriber, NewEntry, write);
				[#subscriber{disconnect = true}] ->
					ok
			end
		end,
		mnesia:transaction(F)
	of
		{atomic, ok} ->
			Answer = #diameter_nas_app_STA{'Session-Id' = SessionId,
					'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
					'Origin-Host' = OHost, 'Origin-Realm' = ORealm},
			{reply, Answer, State}
	catch
		_:_ ->
			Answer = #diameter_nas_app_STA{'Session-Id' = SessionId,
					'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					'Origin-Host' = OHost, 'Origin-Realm' = ORealm},
			{reply, Answer, State}
	end.
%% @hidden
request1(OHost, ORealm, Request, #state{handlers = Handlers} = State) ->
	SessionId = get_session_id(Request),
	try
		#diameter_nas_app_AAR{'Auth-Request-Type' = Type, 'User-Name' = UserName,
				'User-Password' = Password} = Request,
		case gb_trees:lookup(SessionId, Handlers) of
			none ->
				SimpleAuthSup = State#state.simple_auth_sup,
				case {UserName, Password} of
					{UserName, Password} when (UserName /= undefined andalso
							Password /= undefined) ->
						{Fsm, NewState} = start_fsm(SimpleAuthSup, 1, SessionId, Type, OHost, ORealm, UserName,
							Password, State),
						Answer = gen_fsm:sync_send_all_state_event(Fsm, diameter_request),
						{reply, Answer, NewState};
					_ ->
						Answer = #diameter_nas_app_AAA{
								'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
								'Origin-Host' = OHost, 'Origin-Realm' = ORealm, 'Session-Id' = SessionId},
						{reply, Answer, State}
					end;
			{value, _Fsm} ->
				Answer = #diameter_nas_app_AAA{'Session-Id' = SessionId,
						'Auth-Application-Id' = 1, 'Auth-Request-Type' = Type,
						'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						'Origin-Host' = OHost, 'Origin-Realm' = ORealm },
				{reply, Answer, State}
		end
	catch
		_:_ ->
			Error = #diameter_nas_app_AAA{
					'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					'Origin-Host' = OHost, 'Origin-Realm' = ORealm, 'Session-Id' = SessionId},
			{reply, Error, State}
	end.

%% @hidden
-spec start_fsm(AuthSup, AppId, SessionId, AuthRequestType, OHost,
		ORealm, UserName, Password, State) -> NewState
	when
		AuthSup :: pid(),
		AppId :: non_neg_integer(),
		SessionId :: string(),
		AuthRequestType :: 1..3,
		OHost :: string(),
		ORealm :: string(),
		UserName:: string(),
		Password :: string(),
		State :: state(),
		NewState :: state() | {Fsm, State},
		Fsm :: undefined | pid().
start_fsm(AuthSup, AppId, SessId, Type, OHost, ORealm, UserName,
			Password, #state{handlers = Handlers} = State) ->
	StartArgs = [diameter, SessId, AppId, Type, OHost, ORealm, UserName, Password],
	ChildSpec = [StartArgs, []],
	case supervisor:start_child(AuthSup, ChildSpec) of
		{ok, Fsm} ->
			link(Fsm),
			NewHandlers = gb_trees:enter(SessId, Fsm, Handlers),
			{Fsm, State#state{handlers = NewHandlers}};
		{error, Reason} ->
			error_logger:error_report(["Error starting session handler",
					{error, Reason}, {supervisor, AuthSup},{session_id, SessId}]),
		%	Answer = #diameter_nas_app_AAA{'Session-Id' = SessId,
		%			'Auth-Application-Id' = 1, 'Auth-Request-Type' = 1,
		%			'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
		%			'Origin-Host' = OHost, 'Origin-Realm' = ORealm },
			{undefined, State}
	end.

-spec get_session_id(Request) -> SessionId
	when
		Request :: #diameter_nas_app_AAR{},
		SessionId :: string().
%% @doc Return value for session id in Diameter Request.
%% @hidden
get_session_id(Request) when is_record(Request, diameter_nas_app_AAR) ->
	Request#diameter_nas_app_AAR.'Session-Id'.

