%%% ocs_log.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016-2017 SigScale Global Inc.
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
%%% @doc This library module implements function used in handling logging
%%% 	in the {@link //ocs. ocs} application.
%%%
-module(ocs_log).
-copyright('Copyright (c) 2016-2017 SigScale Global Inc.').

%% export the ocs_log public API
-export([radius_acct_open/0, radius_acct_log/4, radius_acct_close/0]).
-export([radius_auth_open/0, radius_auth_log/5, radius_auth_close/0]).
-export([ipdr_log/3, get_range/3, dump_file/2]).
-export([date/1, iso8601/1]).

%% export the ocs_log private API
-export([]).

-include("ocs_log.hrl").
-include_lib("radius/include/radius.hrl").

-define(RADACCT, radius_acct).
-define(RADAUTH, radius_auth).

%%----------------------------------------------------------------------
%%  The ocs_log public API
%%----------------------------------------------------------------------

-spec radius_acct_open() -> Result
	when
		Result :: ok | {error, Reason :: term()}.
%% @doc Open the accounting log for logging events.
radius_acct_open() ->
	{ok, Directory} = application:get_env(ocs, acct_log_dir),
	case file:make_dir(Directory) of
		ok ->
			radius_acct_open1(Directory);
		{error, eexist} ->
			radius_acct_open1(Directory);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
radius_acct_open1(Directory) ->
	{ok, LogSize} = application:get_env(ocs, acct_log_size),
	{ok, LogFiles} = application:get_env(ocs, acct_log_files),
	Log = ?RADACCT,
	FileName = Directory ++ "/" ++ atom_to_list(Log),
	case disk_log:open([{name, Log}, {file, FileName},
					{type, wrap}, {size, {LogSize, LogFiles}}]) of
		{ok, Log} ->
			ok;
		{repaired, Log, _Recovered, _Bad} ->
			ok;
		{error, Reason} ->
			Descr = lists:flatten(disk_log:format_error(Reason)),
			Trunc = lists:sublist(Descr, length(Descr) - 1),
			error_logger:error_report([Trunc, {module, ?MODULE},
					{log, Log}, {error, Reason}]),
			{error, Reason}
	end.

-spec radius_acct_log(Server, Client, Type, Attributes) -> Result
	when
		Server :: {Address :: inet:ip_address(),
				Port :: integer()},
		Client :: {Address :: inet:ip_address(),
				Port :: integer()},
		Type :: on | off | start | stop | interim,
		Attributes :: radius_attributes:attributes(),
		Result :: ok | {error, Reason :: term()}.
%% @doc Write an accounting event to disk log.
radius_acct_log(Server, Client, Type, Attributes) ->
	TS = erlang:system_time(millisecond),
	Event = {TS, node(), Server, Client, Type, Attributes},
	disk_log:log(?RADACCT, Event).

-spec radius_acct_close() -> Result
	when
		Result :: ok | {error, Reason :: term()}.
%% @doc Close accounting disk log.
radius_acct_close() ->
	case disk_log:close(?RADACCT) of
		ok ->
			ok;
		{error, Reason} ->
			Descr = lists:flatten(disk_log:format_error(Reason)),
			Trunc = lists:sublist(Descr, length(Descr) - 1),
			error_logger:error_report([Trunc, {module, ?MODULE},
					{log, ?RADACCT}, {error, Reason}]),
			{error, Reason}
	end.

-spec radius_auth_open() -> Result
	when
		Result :: ok | {error, Reason :: term()}.
%% @doc Open the authorization log for logging events.
radius_auth_open() ->
	{ok, Directory} = application:get_env(ocs, auth_log_dir),
	case file:make_dir(Directory) of
		ok ->
			radius_auth_open1(Directory);
		{error, eexist} ->
			radius_auth_open1(Directory);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
radius_auth_open1(Directory) ->
	{ok, LogSize} = application:get_env(ocs, auth_log_size),
	{ok, LogFiles} = application:get_env(ocs, auth_log_files),
	Log = ?RADAUTH,
	FileName = Directory ++ "/" ++ atom_to_list(Log),
	case disk_log:open([{name, Log}, {file, FileName},
					{type, wrap}, {size, {LogSize, LogFiles}}]) of
		{ok, Log} ->
			ok;
		{repaired, Log, _Recovered, _Bad} ->
			ok;
		{error, Reason} ->
			Descr = lists:flatten(disk_log:format_error(Reason)),
			Trunc = lists:sublist(Descr, length(Descr) - 1),
			error_logger:error_report([Trunc, {module, ?MODULE},
					{log, Log}, {error, Reason}]),
			{error, Reason}
	end.

-spec radius_auth_log(Server, Client, Type, RequestAttributes,
		ResponseAttributes) -> Result
	when
		Server :: {Address :: inet:ip_address(),
				Port :: integer()},
		Client :: {Address :: inet:ip_address(),
				Port :: integer()},
		Type :: accept | reject | change,
		RequestAttributes :: radius_attributes:attributes(),
		ResponseAttributes :: radius_attributes:attributes(),
		Result :: ok | {error, Reason :: term()}.
%% @doc Write an authorization event to disk log.
radius_auth_log(Server, Client, Type, RequestAttributes, ResponseAttributes) ->
	TS = erlang:system_time(millisecond),
	Event = {TS, node(), Server, Client, Type,
			RequestAttributes, ResponseAttributes},
	disk_log:log(?RADAUTH, Event).

-spec radius_auth_close() -> Result
	when
		Result :: ok | {error, Reason :: term()}.
%% @doc Close authorization disk log.
radius_auth_close() ->
	case disk_log:close(?RADAUTH) of
		ok ->
			ok;
		{error, Reason} ->
			Descr = lists:flatten(disk_log:format_error(Reason)),
			Trunc = lists:sublist(Descr, length(Descr) - 1),
			error_logger:error_report([Trunc, {module, ?MODULE},
					{log, ?RADAUTH}, {error, Reason}]),
			{error, Reason}
	end.

-spec ipdr_log(File, Start, End) -> Result
	when
		File :: file:filename(),
		Start :: calendar:datetime() | pos_integer(),
		End :: calendar:datetime() | pos_integer(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Log accounting records within range to new IPDR disk log.
%%
%% 	Creates a new {@link //kernel/disk_log:log(). disk_log:log()},
%% 	or overwrites an existing, with filename `File'. The log starts
%% 	with a `#ipdrDoc{}' header, is followed by `#ipdr{}' records,
%% 	and ends with a `#ipdrDocEnd{}' trailer.
%%
%% 	The `radius_acct' log is searched for events created between `Start'
%% 	and `End' which may be given as
%% 	`{{Year, Month, Day}, {Hour, Minute, Second}}' or the native
%% 	{@link //erts/erlang:system_time(). erlang:system_time(milliseonds)}.
%%
ipdr_log(File, {{_, _, _}, {_, _, _}} = Start, End) ->
	Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
	Seconds = calendar:datetime_to_gregorian_seconds(Start) - Epoch,
	ipdr_log(File, Seconds * 1000, End);
ipdr_log(File, Start, {{_, _, _}, {_, _, _}} = End) ->
	Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
	Seconds = calendar:datetime_to_gregorian_seconds(End) - Epoch,
	ipdr_log(File, Start, Seconds * 1000);
ipdr_log(File, Start, End) when is_list(File),
		is_integer(Start), is_integer(End) ->
	case disk_log:open([{name, File}, {file, File}, {repair, truncate}]) of
		{ok, IpdrLog} ->
			IpdrDoc = #ipdrDoc{docId = uuid(), version = "3.1",
					creationTime = iso8601(erlang:system_time(millisecond)),
					ipdrRecorderInfo = atom_to_list(node())},
			case disk_log:log(IpdrLog, IpdrDoc) of
				ok ->
					ipdr_log1(IpdrLog, Start, End,
							start_binary_tree(?RADACCT, Start, End));
				{error, Reason} ->
					error_logger:error_report([disk_log:format_error(Reason),
							{module, ?MODULE}, {log, IpdrLog}, {error, Reason}]),
					disk_log:close(IpdrLog),
					{error, Reason}
			end;
		{error, Reason} ->
			error_logger:error_report([disk_log:format_error(Reason),
					{module, ?MODULE}, {file, File}, {error, Reason}]),
			{error, Reason}
	end.
%% @hidden
ipdr_log1(IpdrLog, _Start, _End, {error, Reason}) ->
	error_logger:error_report([disk_log:format_error(Reason),
			{module, ?MODULE}, {log, ?RADACCT}, {error, Reason}]),
	ipdr_log4(IpdrLog, 0);
ipdr_log1(IpdrLog, _Start, _End, eof) ->
	ipdr_log4(IpdrLog, 0);
ipdr_log1(IpdrLog, Start, End, Cont) ->
	ipdr_log2(IpdrLog, Start, End, [], disk_log:chunk(?RADACCT, Cont)).
%% @hidden
ipdr_log2(IpdrLog, _Start, _End, _PrevChunk, {error, Reason}) ->
	error_logger:error_report([disk_log:format_error(Reason),
			{module, ?MODULE}, {log, ?RADACCT}, {error, Reason}]),
	ipdr_log4(IpdrLog, 0);
ipdr_log2(IpdrLog, _Start, _End, [], eof) ->
	ipdr_log4(IpdrLog, 0);
ipdr_log2(IpdrLog, Start, End, PrevChunk, eof) ->
	Fstart = fun(R) when element(1, R) < Start ->
				true;
			(_) ->
				false
	end,
	ipdr_log3(IpdrLog, Start, End, 0,
			{eof, lists:dropwhile(Fstart, PrevChunk)});
ipdr_log2(IpdrLog, Start, End, _PrevChunk, {Cont, [H | T]})
		when element(1, H) < Start ->
	ipdr_log2(IpdrLog, Start, End, T, disk_log:chunk(?RADACCT, Cont));
ipdr_log2(IpdrLog, Start, End, PrevChunk, {Cont, Chunk}) ->
	Fstart = fun(R) when element(1, R) < Start ->
				true;
			(_) ->
				false
	end,
	ipdr_log3(IpdrLog, Start, End, 0,
			{Cont, lists:dropwhile(Fstart, PrevChunk ++ Chunk)}).
%% @hidden
ipdr_log3(IpdrLog, _Start, _End, SeqNum, eof) ->
	ipdr_log4(IpdrLog, SeqNum);
ipdr_log3(IpdrLog, _Start, _End, SeqNum, {error, _Reason}) ->
	ipdr_log4(IpdrLog, SeqNum);
ipdr_log3(IpdrLog, _Start, _End, SeqNum, {eof, []}) ->
	ipdr_log4(IpdrLog, SeqNum);
ipdr_log3(IpdrLog, Start, End, SeqNum, {Cont, []}) ->
	ipdr_log3(IpdrLog, Start, End, SeqNum, disk_log:chunk(?RADACCT, Cont));
ipdr_log3(IpdrLog, _Start, End, SeqNum, {_Cont, [H | _]})
		when element(1, H) > End ->
	ipdr_log4(IpdrLog, SeqNum);
ipdr_log3(IpdrLog, _Start, End, SeqNum, {Cont, [H | T]})
		when element(5, H) == stop ->
	IPDR = ipdr_codec(H),
	NewSeqNum = SeqNum + 1,
	case disk_log:log(IpdrLog, IPDR#ipdr{seqNum = NewSeqNum}) of
		ok ->
			ipdr_log3(IpdrLog, _Start, End, NewSeqNum, {Cont, T});
		{error, Reason} ->
			error_logger:error_report([disk_log:format_error(Reason),
					{module, ?MODULE}, {log, IpdrLog}, {error, Reason}]),
			disk_log:close(IpdrLog),
			{error, Reason}
	end;
ipdr_log3(IpdrLog, Start, End, SeqNum, {Cont, [_ | T]}) ->
	ipdr_log3(IpdrLog, Start, End, SeqNum, {Cont, T}).
%% @hidden
ipdr_log4(IpdrLog, SeqNum) ->
	EndTime = iso8601(erlang:system_time(millisecond)),
	IpdrDocEnd = #ipdrDocEnd{count = SeqNum, endTime = EndTime},
	case disk_log:log(IpdrLog, IpdrDocEnd) of
		ok ->
			case disk_log:close(IpdrLog) of
				ok ->
					ok;
				{error, Reason} ->
					error_logger:error_report([disk_log:format_error(Reason),
							{module, ?MODULE}, {log, IpdrLog}, {error, Reason}]),
					{error, Reason}
			end;
		{error, Reason} ->
			error_logger:error_report([disk_log:format_error(Reason),
					{module, ?MODULE}, {log, IpdrLog}, {error, Reason}]),
			disk_log:close(IpdrLog),
			{error, Reason}
	end.

-spec get_range(Log, Start, End) -> Result
	when
		Log :: disk_log:log(),
		Start :: calendar:datetime() | pos_integer(),
		End :: calendar:datetime() | pos_integer(),
		Result :: [term()].
%% @doc Get all events in a log within a date/time range.
%%
%% @private
get_range(Log, {{_, _, _}, {_, _, _}} = Start, End) ->
	Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
	Seconds = calendar:datetime_to_gregorian_seconds(Start) - Epoch,
	get_range(Log, Seconds * 1000, End);
get_range(Log, Start, {{_, _, _}, {_, _, _}} = End) ->
	Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
	Seconds = calendar:datetime_to_gregorian_seconds(End) - Epoch,
	get_range(Log, Start, Seconds * 1000);
get_range(Log, Start, End) when is_integer(Start), is_integer(End) ->
	get_range(Log, Start, End, start).

-spec dump_file(Log, FileName) -> Result
	when
		Log :: disk_log:log(),
		FileName :: file:filename(),
		Result :: ok | {error, Reason :: term()}.
%% @doc Write all logged records to a file.
%%
dump_file(Log, FileName) when is_list(FileName) ->
	case file:open(FileName, [write]) of
		{ok, IoDevice} ->
			file_chunk(Log, IoDevice, start);
		{error, Reason} ->
			error_logger:error_report([file:format_error(Reason),
					{module, ?MODULE}, {log, Log}, {error, Reason}]),
			{error, Reason}
	end.

-spec date(MilliSeconds) -> Result
	when
		MilliSeconds :: pos_integer(),
		Result :: calendar:datetime().
%% @doc Convert timestamp to date and time.
date(MilliSeconds) when is_integer(MilliSeconds) ->
	Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
	Seconds = Epoch + (MilliSeconds div 1000),
	calendar:gregorian_seconds_to_datetime(Seconds).

-spec iso8601(MilliSeconds) -> Result
	when
		MilliSeconds :: pos_integer(),
		Result :: string().
%% @doc Convert timestamp to ISO 8601 format date and time.
iso8601(MilliSeconds) when is_integer(MilliSeconds) ->
	{{Year, Month, Day}, {Hour, Minute, Second}} = date(MilliSeconds),
	DateFormat = "~4.10.0b-~2.10.0b-~2.10.0b",
	TimeFormat = "T~2.10.0b:~2.10.0b:~2.10.0b.~3.10.0bZ",
	Chars = io_lib:fwrite(DateFormat ++ TimeFormat,
			[Year, Month, Day, Hour, Minute, Second, MilliSeconds rem 1000]),
	lists:flatten(Chars).

uuid() ->
	<<A:32, B:16, C:16, D:16, E:48>> = crypto:strong_rand_bytes(16),
	Format = "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
	Values = [A, B, (C bsr 4) bor 16#4000, (D bsr 2) bor 16#8000, E],
	Chars = io_lib:fwrite(Format, Values),
	lists:flatten(Chars).


%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
file_chunk(Log, IoDevice, Cont) ->
	case disk_log:chunk(Log, Cont) of
		eof ->
			file:close(IoDevice);
		{error, Reason} ->
			error_logger:error_report([file:format_error(Reason),
					{module, ?MODULE}, {log, Log}, {error, Reason}]),
			file:close(IoDevice),
			{error, Reason};
		{NextCont, Terms} ->
			Fun =  fun(Event) ->
						io:fwrite(IoDevice, "~999p~n", [Event])
			end,
			lists:foreach(Fun, Terms),
			file_chunk(Log, IoDevice, NextCont)
	end.

-spec start_binary_tree(Log, Start, End) -> Result
	when
		Log :: disk_log:log(),
		Start :: pos_integer(),
		End :: pos_integer(),
		Result :: eof | disk_log:continuation() | {error, Reason},
		Reason :: term().
%% @doc Binary tree search of multi file wrap disk_log.
%% @private
start_binary_tree(Log, Start, _End) ->
	InfoList = disk_log:info(Log),
	{size, {_MaxBytes, MaxFiles}} = lists:keyfind(size, 1, InfoList),
	StartStep = MaxFiles div 2,
	start_binary_tree(Log, Start, MaxFiles, start, 0, StartStep, StartStep).
%% @hidden
start_binary_tree(_Log, _Start, NumFiles,
		LastCont, _LastStep, _StepSize, NumFiles) ->
	LastCont;
start_binary_tree(_Log, _Start, _NumFiles,
		_LastCont, _LastStep, _StepSize, -1) ->
	eof;
start_binary_tree(Log, Start, NumFiles, LastCont, LastStep, StepSize, Step) ->
	case disk_log:chunk_step(Log, start, Step) of
		{ok, NewCont} ->
			start_binary_tree(Log, Start, NumFiles, LastCont, LastStep,
					StepSize, Step, NewCont, disk_log:chunk(Log, NewCont, 1));
		{error, end_of_log} ->
			LastCont;
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_binary_tree(_Log, Start, _NumFiles, _LastCont, LastStep, 1,
		Step, NewCont, {_, [R]}) when element(1, R) < Start,
		LastStep == (Step + 1) ->
	NewCont;
start_binary_tree(Log, Start, NumFiles, _LastCont, _LastStep, 1,
		Step, NewCont, {_, [R]}) when element(1, R) < Start ->
	start_binary_tree(Log, Start, NumFiles, NewCont, Step, 1, Step + 1);
start_binary_tree(Log, Start, NumFiles, _LastCont, _LastStep, StepSize,
		Step, NewCont, {_, [R]}) when element(1, R) < Start ->
	NewStepSize = StepSize div 2,
	start_binary_tree(Log, Start, NumFiles, NewCont, Step,
			NewStepSize, Step + NewStepSize);
start_binary_tree(_Log, Start, _NumFiles, LastCont, LastStep, 1,
		Step, _NewCont, {_, [R]}) when element(1, R) >= Start,
		LastStep == (Step - 1) ->
	LastCont;
start_binary_tree(Log, Start, NumFiles, _LastCont, _LastStep, 1,
		Step, NewCont, {_, [R]}) when element(1, R) >= Start ->
	start_binary_tree(Log, Start, NumFiles, NewCont, Step, 1, Step - 1);
start_binary_tree(Log, Start, NumFiles, _LastCont, _LastStep, StepSize,
		Step, NewCont, {_, [R]}) when element(1, R) >= Start ->
	NewStepSize = StepSize div 2,
	start_binary_tree(Log, Start, NumFiles, NewCont, Step,
			NewStepSize, Step - NewStepSize);
start_binary_tree(_, _, _, _, _, _, _, _, {error, Reason}) ->
	{error, Reason}.

-spec get_range(Log, Start, End, Cont) -> Result
	when
		Log :: disk_log:log(),
		Start :: pos_integer(),
		End :: pos_integer(),
		Cont :: start | disk_log:continuation(),
		Result :: [term()].
%% @doc Sequentially read 64KB chunks.
%%
%% 	Filters out records before `Start' and after `End'.
%% 	Returns filtered records.
%% @private
get_range(Log, Start, End, Cont) ->
	get_range(Log, Start, End, [], disk_log:chunk(Log, Cont)).
%% @hidden
get_range(_Log, _Start, _End, _PrevChunk, {error, Reason}) ->
	{error, Reason};
get_range(Log, Start, End, PrevChunk, eof) ->
	get_range1(Log, Start, End, {eof, PrevChunk}, []);
get_range(Log, Start, End, _PrevChunk, {Cont, [H | T]})
		when element(1, H) < Start ->
	get_range(Log, Start, End, T, disk_log:chunk(Log, Cont));
get_range(Log, Start, End, PrevChunk, {Cont, Chunk}) ->
	get_range1(Log, Start, End, {Cont, PrevChunk ++ Chunk}, []).
%% @hidden
get_range1(Log, Start, End, {Cont, Chunk}, Acc) ->
	Fstart = fun(R) when element(1, R) < Start ->
				true;
			(_) ->
				false
	end,
	NewChunk = lists:dropwhile(Fstart, Chunk),
	get_range2(Log, End, {Cont, NewChunk}, Acc).
%% @hidden
get_range2(_Log, _End, eof, Acc) ->
	lists:flatten(lists:reverse(Acc));
get_range2(_Log, _End, {error, Reason}, _Acc) ->
	{error, Reason};
get_range2(Log, End, {Cont, Chunk}, Acc) ->
	Fend = fun(R) when element(1, R) =< End ->
				true;
			(_) ->
				false
	end,
	case {Cont, lists:last(Chunk)} of
		{eof, R} when element(1, R) =< End ->
			lists:flatten(lists:reverse([Chunk | Acc]));
		{Cont, R} when element(1, R) =< End ->
			get_range2(Log, End, disk_log:chunk(Log, Cont), [Chunk | Acc]);
		{_, _} ->
			lists:flatten(lists:reverse([lists:takewhile(Fend, Chunk) | Acc]))
	end.

-spec ipdr_codec({TimeStamp, Node, Server, Client, stop, Attributes}) -> IPDR
	when
		TimeStamp :: pos_integer(),
		Node :: node(),
		Server :: {Address, Port},
		Client :: {Address, Port},
		Address :: inet:ip_address(),
		Port :: pos_integer(),
		Attributes :: radius_attributes:attributes(),
		IPDR :: #ipdr{}.
%% @doc Convert `radius_acct' log entry to IPDR log entry.
ipdr_codec({TimeStamp, _Node, _Server, _Client, stop, Attributes}) ->
	IPDR = #ipdr{ipdrCreationTime = iso8601(TimeStamp)},
	ipdr_codec1(TimeStamp, Attributes, IPDR).
%% @private
ipdr_codec1(TimeStamp, Attributes, Acc) ->
	case radius_attributes:find(?AcctDelayTime, Attributes) of
		{ok, DelayTime} ->
			EndTime = TimeStamp - (DelayTime * 1000),
			ipdr_codec2(EndTime, Attributes,
					Acc#ipdr{gmtSessionEndDateTime = iso8601(EndTime)});
		{error, not_found} ->
			ipdr_codec2(TimeStamp, Attributes,
					Acc#ipdr{gmtSessionEndDateTime = iso8601(TimeStamp)})
	end.
%% @hidden
ipdr_codec2(EndTime, Attributes, Acc) ->
	case radius_attributes:find(?AcctSessionTime, Attributes) of
		{ok, Duration} ->
			StartTime = EndTime - (Duration * 1000),
			ipdr_codec3(Attributes,
					Acc#ipdr{gmtSessionStartDateTime = iso8601(StartTime)});
		{error, not_found} ->
			ipdr_codec3(Attributes, Acc)
	end.
%% @hidden
ipdr_codec3(Attributes, Acc) ->
	case radius_attributes:find(?UserName, Attributes) of
		{ok, UserName} ->
			ipdr_codec4(Attributes, Acc#ipdr{username = UserName});
		{error, not_found} ->
			ipdr_codec4(Attributes, Acc)
	end.
%% @hidden
ipdr_codec4(Attributes, Acc) ->
	SessionID = radius_attributes:fetch(?AcctSessionId, Attributes),
	ipdr_codec5(Attributes, Acc#ipdr{acctSessionId = SessionID}).
%% @hidden
ipdr_codec5(Attributes, Acc) ->
	case radius_attributes:find(?FramedIpAddress, Attributes) of
		{ok, Address} ->
			ipdr_codec6(Attributes, Acc#ipdr{userIpAddress = inet:ntoa(Address)});
		{error, not_found} ->
			ipdr_codec6(Attributes, Acc)
	end.
%% @hidden
ipdr_codec6(Attributes, Acc) ->
	case radius_attributes:find(?CallingStationId, Attributes) of
		{ok, StationID} ->
			ipdr_codec7(Attributes, Acc#ipdr{callingStationId = StationID});
		{error, not_found} ->
			ipdr_codec7(Attributes, Acc)
	end.
%% @hidden
ipdr_codec7(Attributes, Acc) ->
	case radius_attributes:find(?CalledStationId, Attributes) of
		{ok, StationID} ->
			ipdr_codec8(Attributes, Acc#ipdr{calledStationId = StationID});
		{error, not_found} ->
			ipdr_codec8(Attributes, Acc)
	end.
%% @hidden
ipdr_codec8(Attributes, Acc) ->
	case radius_attributes:find(?NasIpAddress, Attributes) of
		{ok, Address} ->
			ipdr_codec9(Attributes, Acc#ipdr{nasIpAddress = inet:ntoa(Address)});
		{error, not_found} ->
			ipdr_codec9(Attributes, Acc)
	end.
%% @hidden
ipdr_codec9(Attributes, Acc) ->
	case radius_attributes:find(?NasIdentifier, Attributes) of
		{ok, Identifier} ->
			ipdr_codec10(Attributes, Acc#ipdr{nasId = Identifier});
		{error, not_found} ->
			ipdr_codec10(Attributes, Acc)
	end.
%% @hidden
ipdr_codec10(Attributes, Acc) ->
	case radius_attributes:find(?AcctSessionTime, Attributes) of
		{ok, SessionTime} ->
			ipdr_codec11(Attributes, Acc#ipdr{sessionDuration = SessionTime});
		{error, not_found} ->
			ipdr_codec11(Attributes, Acc)
	end.
%% @hidden
ipdr_codec11(Attributes, Acc) ->
	Octets = radius_attributes:fetch(?AcctInputOctets, Attributes),
	case radius_attributes:find(?AcctInputGigawords, Attributes) of
		{ok, GigaWords} ->
			GigaOctets = (GigaWords * (16#ffffffff + 1)) + Octets,
			ipdr_codec12(Attributes, Acc#ipdr{inputOctets = GigaOctets});
		{error, not_found} ->
			ipdr_codec12(Attributes, Acc#ipdr{inputOctets = Octets})
	end.
%% @hidden
ipdr_codec12(Attributes, Acc) ->
	Octets = radius_attributes:fetch(?AcctOutputOctets, Attributes),
	case radius_attributes:find(?AcctOutputGigawords, Attributes) of
		{ok, GigaWords} ->
			GigaOctets = (GigaWords * (16#ffffffff + 1)) + Octets,
			ipdr_codec13(Attributes, Acc#ipdr{outputOctets = GigaOctets});
		{error, not_found} ->
			ipdr_codec13(Attributes, Acc#ipdr{outputOctets = Octets})
	end.
%% @hidden
ipdr_codec13(Attributes, Acc) ->
	case radius_attributes:find(?Class, Attributes) of
		{ok, Class} ->
			ipdr_codec14(Attributes, Acc#ipdr{class = Class});
		{error, not_found} ->
			ipdr_codec14(Attributes, Acc)
	end.
%% @hidden
ipdr_codec14(Attributes, Acc) ->
	case radius_attributes:find(?AcctTerminateCause, Attributes) of
		{ok, Cause} ->
			Acc#ipdr{sessionTerminateCause = Cause};
		{error, not_found} ->
			Acc
	end.

