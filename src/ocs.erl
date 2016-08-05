%%% ocs.erl
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
%%% @doc This library module implements the public API for the
%%% 	{@link //ocs. ocs} application.
%%%
-module(ocs).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

%% export the ocs public API
-export([add_client/2, find_client/1]).
-export([add_user/3, find_user/1]).
-export([log_file/1]).
-export([generate_password/0]).

%% export the ocs private API
-export([install/1]).

%% define client table entries record
-record(radius_client, {address, secret}).

%% define user table entries record
-record(radius_user, {name, password, attributes}).

-define(WAITFORSCHEMA, 10000).
-define(WAITFORTABLES, 10000).

-define(LOGNAME, radius_acct).

%%----------------------------------------------------------------------
%%  The ocs public API
%%----------------------------------------------------------------------

-spec add_client(Address :: inet:ip_address(), Secret :: string()) ->
	Result :: ok | {error, Reason :: term()}.
%% @doc Store the shared secret for a RADIUS client.
%%
add_client(Address, Secret) when is_list(Address), is_list(Secret) ->
	{ok, AddressTuple} = inet_parse:address(Address),
	add_client(AddressTuple, Secret);
add_client(Address, Secret) when is_tuple(Address), is_list(Secret) ->
	F = fun() ->
				R = #radius_client{address = Address, secret = Secret},
				mnesia:write(R)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_client(Address :: inet:ip_address()) ->
	Result :: {ok, Secret :: string()} | error.
%% @doc Look up the shared secret for a RADIUS client.
%%
find_client(Address) when is_list(Address) ->
	{ok, AddressTuple} = inet_parse:address(Address),
	find_client(AddressTuple);
find_client(Address) when is_tuple(Address) ->
	F = fun() ->
				mnesia:read(radius_client, Address, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#radius_client{secret = Secret}]} ->
			{ok, Secret};
		{atomic, []} ->
			error;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec add_user(UserName :: string(), Password :: string(),
		Attributes :: binary() | [byte()]) -> ok | {error, Reason :: term()}.
%% @doc Store the password and static attributes for a user.
%%
add_user(UserName, Password, Attributes) when is_list(UserName),
		is_list(Password), (is_list(Attributes) orelse is_binary(Attributes)) -> 
	F = fun() ->
				R = #radius_user{name = UserName, password = Password,
						attributes = Attributes},
				mnesia:write(R)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_user(UserName :: string()) ->
	Result :: {ok, Password :: string(),
		Attributes :: binary() | [byte()]} | error.
%% @doc Look up a user and return the password and attributes assigned.
%%
find_user(UserName) when is_list(UserName) ->
	F = fun() ->
				mnesia:read(radius_user, UserName, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#radius_user{password = Password, attributes = Attributes}]} ->
			{ok, Password, Attributes};
		{atomic, []} ->
			error;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec log_file(FileName :: string()) -> ok.
%% @doc Write all logged accounting records to a file.
%% 
log_file(FileName) when is_list(FileName) ->
   {ok, IODevice} = file:open(FileName, [write]),
   file_chunk(?LOGNAME, IODevice, start).

%%----------------------------------------------------------------------
%%  The ocs private API
%%----------------------------------------------------------------------

-spec install(Nodes :: [node()]) -> {ok, Tables :: [atom()]}.
%% @doc Initialize a new installation.
%% 	`Nodes' is a list of the nodes where the 
%% 	{@link //ocs. ocs} application will run.
%% 	An mnesia schema should be created and mnesia started on
%% 	all nodes before running this function. e.g.&#058;
%% 	```
%% 		1> mnesia:create_schema([node()]).
%% 		ok
%% 		2> mnesia:start().
%% 		ok
%% 		3> {@module}:install([node()]).
%% 		{ok,[radius_client,radius_user]}
%% 		ok
%% 	'''
%%
%% @private
%%
install(Nodes) when is_list(Nodes) ->
	try
		case mnesia:wait_for_tables([schema], ?WAITFORSCHEMA) of
			ok ->
				ok;
			SchemaResult ->
				throw(SchemaResult)
		end,
		case mnesia:create_table(radius_client, [{disc_copies, Nodes},
				{attributes, record_info(fields, radius_client)}]) of
			{atomic, ok} ->
				error_logger:info_msg("Created new radius_client table.~n");
			{aborted, {already_exists, radius_client}} ->
				error_logger:warning_msg("Found existing radius_client table.~n");
			T1Result ->
				throw(T1Result)
		end,
		case mnesia:create_table(radius_user, [{disc_copies, Nodes},
				{attributes, record_info(fields, radius_user)}]) of
			{atomic, ok} ->
				error_logger:info_msg("Created new radius_user table.~n");
			{aborted, {already_exists, radius_user}} ->
				error_logger:warning_msg("Found existing radius_user table.~n");
			T2Result ->
				throw(T2Result)
		end,
		Tables = [radius_client, radius_user],
		case mnesia:wait_for_tables(Tables, ?WAITFORTABLES) of
			ok ->
				Tables;
			TablesResult ->
				throw(TablesResult)
		end
	of
		Result -> {ok, Result}
	catch
		throw:Error ->
			mnesia:error_description(Error)
	end.
	
-type password() :: [50..57 | 97..107 | 109..110 | 112..122].
-spec generate() -> password().
%% @equiv generate(12)
generate() ->
	generate(12).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec generate(Length :: pos_integer()) -> password().
%% Generate a random password.
%% @private
generate(Length) when Length > 0 ->
	Charset = charset(),
	NumChars = length(Charset),
	Random = crypto:strong_rand_bytes(Length),
	generate(Random, Charset, NumChars,[]).
%% @hidden
generate(<<N, Rest/binary>>, Charset, NumChars, Acc) ->
	CharNum = (N rem NumChars) + 1,
	NewAcc = [lists:nth(CharNum, Charset) | Acc],
	generate(Rest, Charset, NumChars, NewAcc);
generate(<<>>, _Charset, _NumChars, Acc) ->
	Acc.

-spec charset() -> Charset :: password().
%% @doc Returns the table of valid characters for passwords.
%% @private
charset() ->
	C1 = lists:seq($2, $9),
	C2 = lists:seq($a, $k),
	C3 = lists:seq($m, $n),
	C4 = lists:seq($p, $z),
	lists:append([C1, C2, C3, C4]).	

%% @hidden
file_chunk(Log, IODevice, Continuation) ->
	case disk_log:chunk(Log, Continuation) of
		eof ->
			file:close(IODevice);
		{error, Reason} ->
			file:close(IODevice),
			exit(Reason);
		{Continuation2, Terms} ->
			Fun =  fun(Event) ->
						io:fwrite(IODevice, "~999p~n", [Event])
			end,
			lists:foreach(Fun, Terms),
			file_chunk(Log, IODevice, Continuation2)
	end.

