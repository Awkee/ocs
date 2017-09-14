%%% ocs_rest_res_balance.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //ocs. ocs} application.
%%%
-module(ocs_rest_res_product).
-copyright('Copyright (c) 2016 - 2017 SigScale Global Inc.').

-export([content_types_accepted/0, content_types_provided/0]).

-export([add_product/1]).
-export([get_product/1, get_products/1]).
-export([on_patch_product/3]).

-include_lib("radius/include/radius.hrl").
-include("ocs.hrl").

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json", "application/json-patch+json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/json"].

-spec add_product(ReqData) -> Result when
	ReqData	:: [tuple()],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 500 .
%% @doc Respond to `POST /catalogManagement/v1/product' and
%% add a new `product'
add_product(ReqData) ->
	try
		{struct, Object} = mochijson:decode(ReqData),
		Name = prod_name(erlang_term, Object),
		IsBundle = prod_isBundle(erlang_term, Object),
		Status = prod_status(erlang_term, Object),
		ValidFor = prod_vf(erlang_term, Object),
		Descirption = prod_description(erlang_term, Object),
		StartDate = prod_sdate(erlang_term, Object),
		TerminationDate = prod_tdate(erlang_term, Object),
		case prod_offering_price(erlang_term, Object) of
			{error, StatusCode} ->
				{error, StatusCode};
			Price ->
				Product = #product{price = Price, name = Name, valid_for = ValidFor,
					is_bundle = IsBundle, status = Status, start_date = StartDate,
					termination_date = TerminationDate, description = Descirption},
				case add_product1(Product) of
					ok ->
						add_product2(Name, Object);
					{error, StatusCode} ->
						{error, StatusCode}
				end
		end
	catch
		_:_ ->
			{error, 400}
	end.
%% @hidden
add_product1(Products) ->
	F1 = fun() ->
		ok = mnesia:write(product, Products, write)
	end,
	case mnesia:transaction(F1) of
		{atomic, ok} ->
			ok;
		{aborted, _} ->
			{error, 500}
	end.
%% @hidden
add_product2(ProdId, JsonResponse) ->
	Id = {id, ProdId},
	Json = {struct, [Id | JsonResponse]},
	Body = mochijson:encode(Json),
	Location = "/catalogManagement/v1/product/" ++ ProdId,
	Headers = [{location, Location}],
	{ok, Headers, Body}.

-spec get_product(ProdID) -> Result when
	ProdID	:: string(),
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /productInventoryManagement/v1/product/{id}' and
%% retrieve a `product' details
get_product(ProductID) ->
	F = fun() ->
		case mnesia:read(product, ProductID) of
			[Product] ->
				Product;
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, Prod} ->
			get_product1(Prod);
		{aborted, {throw, not_found}} ->
			{error, 404};
		{aborted, _} ->
			{error, 500}
	end.
%% @hidden
get_product1(Prod) ->
	ID = prod_id(json, Prod),
	Descirption = prod_description(json, Prod),
	Href = prod_href(json, Prod),
	ValidFor = prod_vf(json, Prod),
	IsBundle = prod_isBundle(json, Prod),
	Name = prod_name(json, Prod),
	Status = prod_status(json, Prod),
	StartDate = prod_sdate(json, Prod),
	TerminationDate = prod_tdate(json, Prod),
	case prod_offering_price(json, Prod) of
		{error, StatusCode} ->
			{error, StatusCode};
		OfferPrice ->
			Json = {struct, [ID, Descirption, Href, StartDate,
				TerminationDate, IsBundle, Name, Status, ValidFor,
				OfferPrice]},
			Body = mochijson:encode(Json),
			Headers = [{content_type, "application/json"}],
			{ok, Headers, Body}
	end.

-define(CHUNKSIZE, 100).

-spec get_products(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /productInventoryManagement/v1/product' and
%% retrieve all `product' details
%% @todo Filtering
get_products(_Query) ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun(F, start, Acc) ->
				F(F, mnesia:select(product, MatchSpec,
						?CHUNKSIZE, read), Acc);
			(_F, '$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
			(_F, {error, Reason}, _Acc) ->
				{error, Reason};
			(F,{Product, Cont}, Acc) ->
				F(F, mnesia:select(Cont), [Product | Acc])
	end,
	case mnesia:transaction(F, [F, start, []]) of
		{aborted, _} ->
			{error, 500};
		{atomic, Products} ->
			get_products1(Products, [])
	end.
%% @hidden
get_products1([], Acc) ->
	Json = {array, Acc},
	Body = mochijson:encode(Json),
	Headers = [{content_type, "application/json"}],
	{ok, Headers, Body};
get_products1([Prod | T], Acc) ->
	try
		ID = prod_id(json, Prod),
		Descirption = prod_description(json, Prod),
		Href = prod_href(json, Prod),
		ValidFor = prod_vf(json, Prod),
		IsBundle = prod_isBundle(json, Prod),
		Name = prod_name(json, Prod),
		Status = prod_status(json, Prod),
		StartDate = prod_sdate(json, Prod),
		TerminationDate = prod_tdate(json, Prod),
		case prod_offering_price(json, Prod) of
			{error, StatusCode} ->
				{error, StatusCode};
			OfferPrice ->
			Json = {struct, [ID, Descirption, Href, StartDate,
					TerminationDate, IsBundle, Name, Status, ValidFor,
					OfferPrice]},
			get_products1(T, [Json | Acc])
		end
	catch
		_:_ ->
			{error, 500}
	end.

-spec on_patch_product(ProdId, Etag, ReqData) -> Result
	when
		ProdId	:: string(),
		Etag		:: undefined | list(),
		ReqData	:: [tuple()],
		Result	:: {ok, Headers, Body} | {error, Status},
		Headers	:: [tuple()],
		Body		:: iolist(),
		Status	:: 400 | 500 .
%% @doc Respond to `PATCH /productInventoryManagement/v1/product/{id}' and
%% apply object notation patch for `product'
%% RFC6902 `https://tools.ietf.org/html/rfc6902'
on_patch_product(ProdId, Etag, ReqData) ->
	try
		{array, OpList} = mochijson:decode(ReqData),
		case exe_jsonpatch_ON(ProdId, Etag, OpList) of
			{error, StatusCode} ->
				{error, StatusCode};
			Product ->
				Json = [],
				Body = mochijson:encode(Json),
				Headers = [{content_type, "application/json"}],
				{ok, Headers, Body}
		end

	catch
		_:_ ->
			{error, 400}
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------
-spec prod_offering_price(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: [#price{}] | list() | {error, Status},
		Status	:: 400.
%% @doc construct list of product
%% @private
prod_offering_price(erlang_term, []) ->
	{error, 400};
prod_offering_price(erlang_term, Json) ->
	{_, {array, ProdOfPrice}} = lists:keyfind("productOfferingPrice", 1, Json),
	case po_price(erlang_term, ProdOfPrice, []) of
		{error, Status} ->
			{error, Status};
		Prices ->
			Prices
	end;
prod_offering_price(json, Product) ->
	case po_price(json, Product#product.price, []) of
		{error, Status} ->
			{error, Status};
		ProdOfPrice ->
			{"productPrice", {array, ProdOfPrice}}
	end.

-spec po_price(Prefix, ProductOfPrice, Prices) -> Result
	when
		Prefix	:: erlang_term | json,
		ProductOfPrice	:: list() | [#price{}],
		Prices	::	list(),
		Result	:: [#price{}] | list() | {error, Status},
		Status	:: 400 | 500.
%% @hidden
po_price(erlang_term, [], Prices) ->
	Prices;
po_price(erlang_term, [{struct, Object} | T], Prices) ->
	try
		ProdName = prod_price_name(erlang_term, Object),
		{ProdSTime, ProdETime} = prod_price_vf(erlang_term, Object),
		ProdPriceType = prod_price_type(erlang_term, Object),
		{_, {struct, ProdPriceObj}} = lists:keyfind("price", 1, Object),
		ProdAmount = prod_price_price_amount(erlang_term, ProdPriceObj),
		CurrencyCode = prod_price_price_c_code(erlang_term, ProdPriceObj),
		ProdVF = prod_price_vf(erlang_term, Object),
		RCPeriod = prod_price_rc_period(erlang_term, Object),
		ProdDescirption = prod_price_description(erlang_term, Object),
		ProdValidity = ProdETime - ProdSTime,
		{ProdUnits, ProdSize} = prod_price_ufm(erlang_term, Object),
		Size = product_size(ProdUnits, octets, ProdSize),
		Price1 = #price{name = ProdName, description = ProdDescirption,
				type = ProdPriceType, units = ProdUnits, size = Size, valid_for = ProdVF,
				currency = CurrencyCode, period = RCPeriod, validity = ProdValidity,
				amount = ProdAmount},
		case lists:keyfind("productOfferPriceAlteration", 1, Object) of
			false ->
				po_price(erlang_term, T, [Price1 | Prices]);
			{_, {struct, ProdAlterObj}} ->
				case po_alteration(erlang_term, ProdAlterObj) of
					{error, Status} ->
						{error, Status};
					Alteration ->
						Price2 = Price1#price{alteration = Alteration},
						po_price(erlang_term, T, [Price2 | Prices])
				end
		end
	catch
		_:_ ->
			{error, 400}
	end;
po_price(json, [], Prices) ->
	Prices;
po_price(json, [Price | T], Prices) when is_record(Price, price) ->
	try
		Name = prod_price_name(json, Price),
		ValidFor = prod_price_vf(json, Price),
		PriceType = prod_price_type(json, Price),
		Amount = prod_price_price_amount(json, Price),
		CurrencyCode = prod_price_price_c_code(json, Price),
		PriceObj = {"price", {struct, [Amount, CurrencyCode]}},
		RCPeriod = prod_price_rc_period(json, Price),
		Description = prod_price_description(json, Price),
		UOMeasure = prod_price_ufm(json, Price),
		if
			Price#price.alteration == undefined ->
				Price1 = {struct, [Name, Description, ValidFor,
					PriceType, PriceObj, UOMeasure, RCPeriod]},
				po_price(json, T, [Price1 | Prices]);
			true ->
				case po_alteration(json, Price#price.alteration) of
					{error, Status} ->
						{error, Status};
					Alteration ->
						Price1 = {struct, [Name, Description, PriceType,
							ValidFor, PriceObj, UOMeasure, RCPeriod, Alteration]},
						po_price(json, T, [Price1 | Prices])
				end
		end
	catch
		_:_ ->
			{error, 500}
	end.

-spec po_alteration(Prefix, ProdAlterObj) -> Result
	when
		Prefix	:: erlang_term | json,
		ProdAlterObj :: list(),
		Result	:: #alteration{} | {error, Status},
		Status	:: 400 | 500.
%% @private
po_alteration(erlang_term, ProdAlterObj) ->
	try
		ProdAlterName = prod_price_alter_name(erlang_term, ProdAlterObj),
		ProdAlterVF = prod_price_alter_vf(erlang_term, ProdAlterObj),
		ProdAlterPriceType = prod_price_alter_price_type(erlang_term, ProdAlterObj),
		{_, {struct, ProdAlterPriceObj}} = lists:keyfind("price", 1, ProdAlterObj),
		ProdAlterAmount = prod_price_alter_amount(erlang_term, ProdAlterPriceObj),
		ProdAlterDescirption = prod_price_alter_description(erlang_term, ProdAlterObj),
		{ProdAlterUnits, ProdAlterSize} = prod_price_ufm(erlang_term, ProdAlterObj),
		AlterSize = product_size(ProdAlterUnits, octets, ProdAlterSize),
		#alteration{name = ProdAlterName, description = ProdAlterDescirption,
			valid_for = ProdAlterVF, units = ProdAlterUnits, size = AlterSize,
			amount = ProdAlterAmount, type = ProdAlterPriceType}
	catch
		_:_ ->
			{error, 400}
	end;
po_alteration(json, ProdAlter) when is_record(ProdAlter, alteration)->
	try
		Name = prod_price_alter_name(json, ProdAlter),
		ValidFor = prod_price_alter_vf(json, ProdAlter),
		PriceType = prod_price_alter_price_type(json, ProdAlter),
		UFM  = prod_price_ufm(json, ProdAlter),
		Description = prod_price_alter_description(json, ProdAlter),
		Amount = prod_price_alter_amount(json, ProdAlter),
		PriceObj = {struct, [Amount]},
		Price = {"price", PriceObj},
		{"prodPriceAlteration",
			{struct, [Name, Description, PriceType, ValidFor, UFM, Price]}}
	catch
		_:_ ->
			{error, 500}
	end.

-spec prod_id(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: string() | tuple().
%% @private
prod_id(json, Product) ->
	{"id", Product#product.name}.

-spec prod_name(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: string() | tuple().
%% @private
prod_name(erlang_term, Product) ->
	{_, Name} = lists:keyfind("name", 1, Product),
	Name;
prod_name(json, Prod) ->
	{"name", Prod#product.name}.

-spec prod_description(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: undefined | string() | tuple().
%% @private
prod_description(erlang_term, Product) ->
	proplists:get_value("description", Product, undefined);
prod_description(json, Product) ->
	{"description", Product#product.description}.

-spec prod_href(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: undefined | string() | tuple().
%% @private
prod_href(json, Product) ->
	{"href", "/product/product/" ++ Product#product.name}.

-spec prod_isBundle(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: boolean() | tuple().
%% @private
prod_isBundle(erlang_term, Product) ->
	case lists:keyfind("isBundle", 1, Product) of
		{"isBundle", "true"} -> true;
		_ -> false
	end;
prod_isBundle(json, Product) ->
	{"isBundle", Product#product.is_bundle}.

-spec prod_status(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: string() | tuple().
%% @private
prod_status(erlang_term, Product) ->
	case lists:keyfind("lifecycleStatus", 1, Product) of
		{_, FindStatus} ->
			find_status(FindStatus);
		false ->
			"active"
	end;
prod_status(json, Product) ->
	{"status", Product#product.status}.

-spec prod_sdate(Prefix, Product) -> Result
	when
		Prefix :: erlang_term | json,
		Product :: list() | #product{},
		Result :: undefined | tuple().
%% @private
prod_sdate(erlang_term, Product) ->
	case lists:keyfind("startDate", 1, Product) of
		{_, SD} ->
			ocs_rest:iso8601(SD);
		false ->
			undefined
	end;
prod_sdate(json, Product) ->
	case Product#product.start_date of
		undefined ->
			{"startDate", ""};
		SD ->
			{"startDate", ocs_rest:iso8601(SD)}
	end.

-spec prod_tdate(Prefix, Product) -> Result
	when
		Prefix :: erlang_term | json,
		Product :: list() | #product{},
		Result :: undefined | tuple().
%% @private
prod_tdate(erlang_term, Product) ->
	case lists:keyfind("terminationDate", 1, Product) of
		{_, SD} ->
			ocs_rest:iso8601(SD);
		false ->
			undefined
	end;
prod_tdate(json, Product) ->
	case Product#product.termination_date of
		undefined ->
			{"terminationDate", ""};
		SD ->
			{"terminationDate", ocs_rest:iso8601(SD)}
	end.

-spec prod_vf(Prefix, Product) -> Result
	when
		Prefix :: erlang_term | json,
		Product :: list() | #product{},
		Result :: tuple().
%% @private
prod_vf(erlang_term, Product) ->
	{_, {struct, VFObj}} = lists:keyfind("validFor", 1, Product),
	{_, SDT} = lists:keyfind("startDateTime", 1, VFObj),
	{_, EDT} = lists:keyfind("endDateTime", 1, VFObj),
	{ocs_rest:iso8601(SDT), ocs_rest:iso8601(EDT)};
prod_vf(json, Product) ->
	case Product#product.valid_for of
		{SDateTime, undefined} ->
			SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
			{"validFor", {struct, [SDT]}};
		{undefined, EDateTime} ->
			EDT = {"endDateTime", ocs_rest:iso8601(EDateTime)},
			{"validFor", {struct, [EDT]}};
		{SDateTime, EDateTime} ->
			SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
			EDT = {"endDateTime", ocs_rest:iso8601(EDateTime)},
			{"validFor", {struct, [SDT, EDT]}}
	end.

-spec prod_price_name(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: string() | tuple().
%% @private
prod_price_name(erlang_term, Price) ->
	{_, Name} = lists:keyfind("name", 1, Price),
	Name;
prod_price_name(json, Price) ->
	{"name", Price#price.name}.

-spec prod_price_description(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: undefined | string() | tuple().
%% @private
prod_price_description(erlang_term, Price) ->
	proplists:get_value("description", Price, undefined);
prod_price_description(json, Price) ->
	{"description", Price#price.description}.

-spec prod_price_vf(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: tuple().
%% @private
prod_price_vf(erlang_term, Price) ->
	{_,  {struct, VFObj}} = lists:keyfind("validFor", 1, Price),
	{_, SDT} = lists:keyfind("startDateTime", 1, VFObj),
	{_, EDT} = lists:keyfind("endDateTime", 1, VFObj),
	{ocs_rest:iso8601(SDT), ocs_rest:iso8601(EDT)};
prod_price_vf(json, Price) ->
	{SDateTime, EDateTime} = Price#price.valid_for,
	SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
	EDT = {"endDateTime", ocs_rest:iso8601(EDateTime)},
	{"validFor", {struct, [SDT, EDT]}}.

-spec prod_price_type(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: atom() | tuple().
%% @private
prod_price_type(erlang_term, Price) ->
	{_, ProdPriceTypeS} = lists:keyfind("priceType", 1, Price),
	price_type(ProdPriceTypeS);
prod_price_type(json, Price) ->
	PPT = price_type(Price#price.type),
	{"priceType", PPT}.

-spec prod_price_price_amount(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: integer() | tuple().
%% @private
prod_price_price_amount(erlang_term, PriceObj) ->
	{_, ProdAmount} = lists:keyfind("taxIncludedAmount", 1, PriceObj),
	ProdAmount;
prod_price_price_amount(json, Price) ->
	{"taxIncludedAmount", Price#price.amount}.

-spec prod_price_price_c_code(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: integer() | tuple().
%% @private
prod_price_price_c_code(erlang_term, PriceObj) ->
		{_, CurrencyCode} = lists:keyfind("currencyCode", 1, PriceObj),
		CurrencyCode;
prod_price_price_c_code(json, Price) ->
	{"currencyCode", Price#price.currency}.

-spec prod_price_rc_period(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: undefined | string() | tuple().
%% @private
prod_price_rc_period(erlang_term, Price) ->
	case lists:keyfind("recurringChargePeriod", 1, Price) of
		{_, RCPeriod} ->
			rc_period(RCPeriod);
		false ->
			undefined
	end;
prod_price_rc_period(json, Price) ->
	case Price#price.period of
		undefined ->
			{"recurringChargePeriod", ""};
		RCPeriod ->
			{"recurringChargePeriod", rc_period(RCPeriod)}
	end.

-spec prod_price_alter_name(Prefix, PAlter) -> Result
	when
		Prefix :: erlang_term | json,
		PAlter :: list() | #alteration{},
		Result :: string() | tuple().
%% @private
prod_price_alter_name(erlang_term, PAlter) ->
	{_, Name} = lists:keyfind("name", 1, PAlter),
	Name;
prod_price_alter_name(json, PAlter) ->
	{"name", PAlter#alteration.name}.

-spec prod_price_alter_vf(Prefix, PAlter) -> Result
	when
		Prefix :: erlang_term | json,
		PAlter :: list() | #alteration{},
		Result :: integer() | tuple().
%% @private
prod_price_alter_vf(erlang_term, PAlter) ->
	{_, {struct, PAlterVF}} = lists:keyfind("validFor", 1, PAlter),
	{_, PAlterSTimeISO} = lists:keyfind("startDateTime", 1, PAlterVF),
	case lists:keyfind("endDateTime", 1, PAlterVF) of
		false ->
			{ocs_rest:iso8601(PAlterSTimeISO), undefined};
		PAlterETime ->
			{ocs_rest:iso8601(PAlterSTimeISO), PAlterETime}
	end;
prod_price_alter_vf(json, PAlter) ->
	ValidFor = PAlter#alteration.valid_for,
	case ValidFor of
		{SDateTime, undefined} ->
			SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
			{"validFor", {struct, [SDT]}};
		{SDateTime, EDateTime} ->
			SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
			EDT = {"endDateTime", ocs_rest:iso8601(EDateTime)},
			{"validFor", {struct, [SDT, EDT]}}
	end.

-spec prod_price_alter_description(Prefix, PAlter) -> Result
	when
		Prefix :: erlang_term | json,
		PAlter :: list() | #alteration{},
		Result :: undefined | string() | tuple().
%% @private
prod_price_alter_description(erlang_term, PAlter) ->
	proplists:get_value("description", PAlter, undefined);
prod_price_alter_description(json, PAlter) ->
	case PAlter#alteration.description of
		undefined ->
			{"description", ""};
		Des ->
			{"description", Des}
	end.

-spec prod_price_alter_price_type(Prefix, PAlter) -> Result
	when
		Prefix :: erlang_term | json,
		PAlter :: list() | #alteration{},
		Result :: undefined | atom().
%% @private
prod_price_alter_price_type(erlang_term, PAlter) ->
	case lists:keyfind("priceType", 1, PAlter) of
		{_, PriceType} ->
			price_type(PriceType);
		false ->
			undefined
	end;
prod_price_alter_price_type(json, PAlter) ->
	case PAlter#alteration.type of
		undefined ->
			{"priceType", ""};
		PT ->
			{"priceType", price_type(PT)}
	end.

-spec prod_price_alter_amount(Prefix, PAlter) -> Result
	when
		Prefix :: erlang_term | json,
		PAlter :: list() | #alteration{},
		Result :: integer() | tuple().
%% @private
prod_price_alter_amount(erlang_term, PAlterPriceObj) ->
	{_, PAlterAmount} = lists:keyfind("taxIncludedAmount", 1,  PAlterPriceObj),
	PAlterAmount;
prod_price_alter_amount(json, PAlter) ->
	{"taxIncludedAmount", PAlter#alteration.amount}.

-spec prod_price_ufm(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: {Units, Size},
		Units		:: undefined | unit_of_measure(),
		Size		:: undefined | pos_integer().
%% @doc return units type and size of measurement of a product
%% @private
prod_price_ufm(erlang_term, Product) ->
	UFM = proplists:get_value("unitOfMeasure", Product, undefined),
	prod_price_ufm_et(UFM);
prod_price_ufm(json, Product) ->
	prod_price_ufm_json1(Product).
%% @hidden
prod_price_ufm_json1(Price) when is_record(Price, price)->
	Size = Price#price.size,
	Units = Price#price.units,
	{"unitOfMeasure", prod_price_ufm_json2(Units, Size)};
prod_price_ufm_json1(Price) when is_record(Price, alteration)->
	Units = Price#alteration.units,
	Size = product_size(octets, Units, Price#alteration.size),
	{"unitOfMeasure", prod_price_ufm_json2(Units, Size)}.
%% @hidden
prod_price_ufm_json2(undefined, _) ->
	"";
prod_price_ufm_json2(Units, undefined) ->
	Units;
prod_price_ufm_json2(Units, Size) when is_number(Size) ->
	prod_price_ufm_json2(Units, integer_to_list(Size));
prod_price_ufm_json2(octets, Size) when is_list(Size) ->
	Size ++ "octets";
prod_price_ufm_json2(gb, Size) when is_list(Size) ->
	Size ++ "GB";
prod_price_ufm_json2(mb, Size) when is_list(Size) ->
	Size ++ "MB";
prod_price_ufm_json2(cents, Size) when is_list(Size) ->
	Size ++ "cents";
prod_price_ufm_json2(seconds, Size) when is_list(Size) ->
	Size ++ "seconds".
%% @hidden
prod_price_ufm_et(undefined) ->
	{undefined, undefined};
prod_price_ufm_et(UFM) ->
	LowerUOM = string:to_lower(UFM),
	prod_price_ufm_et1(LowerUOM).
%% @hidden
prod_price_ufm_et1(UFM) ->
	Suffix = "octets",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{octets, list_to_integer(Size)};
		false ->
			prod_price_ufm_et2(UFM)
	end.
%% @hidden
prod_price_ufm_et2(UFM) ->
	Suffix = "gb",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{gb, list_to_integer(Size)};
		false ->
			prod_price_ufm_et3(UFM)
	end.
%% @hidden
prod_price_ufm_et3(UFM) ->
	Suffix = "mb",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{mb, list_to_integer(Size)};
		false ->
			prod_price_ufm_et4(UFM)
	end.
%% @hidden
prod_price_ufm_et4(UFM) ->
	Suffix = "cents",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{cents, list_to_integer(Size)};
		false ->
			prod_price_ufm_et5(UFM)
	end.
%% @hidden
prod_price_ufm_et5(UFM) ->
	Suffix = "seconds",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{seconds, list_to_integer(Size)};
		false ->
			prod_price_ufm_et6(UFM)
	end.
%% @hidden
prod_price_ufm_et6(_UFM) ->
	{undefined, undefined}.

-spec product_size(UnitsFrom, UnitsTo, Size) -> Result
	when
		UnitsFrom	:: undefined | atom(), % gb | mb | second | cents
		UnitsTo		:: octets,
		Size			:: undefined | pos_integer(),
		Result		:: integer().
%% @private
product_size(UnitsFrom, octets, Size) when
		UnitsFrom == undefined; Size == undefined ->
	0;
product_size(gb, octets, Size) -> Size * 1000000000;
product_size(octets, gb, Size) -> Size div 1000000000;
product_size(mb, octets, Size) -> Size * 1000000;
product_size(octets, mb, Size) -> Size div 1000000;
product_size(_, _, Size) -> Size.

-spec validity_period(StartTime, EndTime) -> Result
	when
		StartTime	:: string(),
		EndTime		:: string(),
		Result		:: pos_integer() | {error, Reason},
		Reason		:: term().
%% @doc return validity period of a product in milliseconds.
%% @private
validity_period(ISOSTime, ISOETime) when is_list(ISOSTime),
		is_list(ISOETime) ->
	case {ocs_rest:iso8601(ISOSTime), ocs_rest:iso8601(ISOETime)} of
		{{error, _}, _} ->
			{error, format_error};
		{_, {error, _}} ->
			{error, format_error};
		{STime, ETime} ->
			ETime - STime
	end.

-spec rc_period(RCPeriod) -> Result
	when
		RCPeriod	:: string(),
		Result	:: valid_period().
%% @doc return valid period
%% @private
rc_period("") -> undefined;
rc_period("yearly") -> yearly;
rc_period("monthly") -> monthly;
rc_period("weekly") -> weekly;
rc_period("daily") -> daily;
rc_period(undefined) -> "";
rc_period(yearly) -> "yearly";
rc_period(monthly) -> "monthly";
rc_period(weekly) -> "weekly";
rc_period(daily) -> "daily".

-spec find_status(StringStatus) -> Status when
	StringStatus	:: string(),
	Status			:: product_status().
%% @doc return life cycle status of the product
%% @private
find_status("active") -> active;
find_status("created") -> created;
find_status("aborted") -> aborted;
find_status("cancelled") -> cancelled;
find_status("suspended") -> suspended;
find_status("terminate") -> terminate;
find_status("pending_active") -> pending_active;
find_status("pending_terminate") -> pending_terminate.

-spec price_type(StringPriceType) -> PriceType when
	StringPriceType :: string() | atom(),
	PriceType		 :: recurring | one_time | usage | string().
%% @private
price_type("usage") -> usage;
price_type("recurring") -> recurring;
price_type("one_time") -> one_time;
price_type(usage) -> "usage";
price_type(recurring) -> "recurring";
price_type(one_time) -> "one_time".

-spec exe_jsonpatch_ON(ProductID, Etag, OperationList) -> Result
	when
		ProductID		:: string() | binary(),
		Etag				:: undefined | tuple(),
		OperationList	:: [tuple()],
		Result			:: list() | {error, StatusCode},
		StatusCode		:: 400 | 404 | 422 | 500.
%% @doc execute object notation json patch
exe_jsonpatch_ON(ProdID, _Etag, OperationList) ->
	F = fun() ->
			case mnesia:read(product, ProdID, write) of
				[Entry] ->
					case ocs_rest:parse(OperationList) of
						{error, invalid_format} ->
							throw(malfored_request);
						Operations ->
							case lists:foldl(fun do_patch/2, Entry, Operations) of
								{error, Reason} ->
									throw(Reason);
								Updatedentry ->
									ok = mnesia:write(Updatedentry),
									Updatedentry
							end
					end;
				[] ->
					throw(not_found)
			end
	end,
	case mnesia:transaction(F) of
		{atomic, Product} ->
			{ok,  Product};
		{aborted, {throw, malfored_request}} ->
			{error, 400};
		{aborted, {throw, not_found}} ->
			{error, 404};
		{aborted, {throw, not_implemented}} ->
			{error, 422};
		{aborted, {throw, unprocessable}} ->
			{error, 422};
		{aborted, _Reason} ->
			{error,  500}
	end.

-spec do_patch(Operation, Product) -> Result
	when
		Operation	:: {Op, Path, Value},
		Product		:: #product{},
		Op				:: replace | add | remove | move | copy | test,
		Path			:: list(),
		Value			:: term(),
		Result		:: #product{} | {error, Reason},
		Reason		:: malfored_request | not_implemented | unprocessable.
%% @doc validate operation and paths for product patch reqeust.
do_patch({replace, Path, Value}, Product) ->
	patch_replace(Path, Value, Product);
do_patch(_, _) ->
	{error, not_implemented}.

patch_replace(["name"], Value, Product) when is_list(Value) ->
	Product#product{name = Value};
patch_replace(["description"], Value, Product) when is_list(Value) ->
	Product#product{description = Value};
patch_replace(["isBundle"], Value, Product) when is_boolean(Value) ->
	Product#product{is_bundle = Value};
patch_replace(["startDate"], Value, Product) when is_list(Value) ->
	SDate = ocs_rest:iso8601(Value),
	Product#product{start_date = SDate};
patch_replace(["terminationDate"], Value, Product) when is_list(Value) ->
	TDate = ocs_rest:iso8601(Value),
	Product#product{termination_date = TDate};
patch_replace(["status"], Value, Product) when is_list(Value) ->
	Status = find_status(Value),
	Product#product{status = Status};
patch_replace(["productPrice" | T], Value, Product) ->
	case patch_replace1(prod_price, T, Value, Product#product.price) of
		{error, Reason} ->
			{error, Reason};
		Price ->
			Product#product{price = Price}
	end;
patch_replace(_, _, _) ->
	{error, unprocessable}.
%% @hidden
patch_replace1(prod_price, [], {array, Values}, _) ->
	try
	F = fun({struct, Obj}, Acc) ->
			F5 = fun(F5, [{"taxIncludedAmount", A} | T], Alter) when is_integer(A) ->
							F5(F5, T, Alter#alteration{amount = A});
						(_, [], Alter) ->
							Alter;
						(_, _, _) ->
							throw(malfored_request)
			end,
			F4 = fun(F4, [{"name", V} | T], Alter) when is_list(V) ->
							NAlter = Alter#alteration{name = V},
							F4(F4, T, NAlter);
						(F4, [{"description", V} | T], Alter) when is_list(V) ->
							NAlter = Alter#alteration{description = V},
							F4(F4, T, NAlter);
						(F4, [{"priceType", V} | T], Alter) when is_list(V) ->
							PT = price_type(V),
							NAlter = Alter#alteration{type = PT},
							F4(F4, T, NAlter);
						(F4, [{"price", {struct, V}} | T], Alter) when is_list(V) ->
							NAlter = F5(F5, V, Alter),
							F4(F4, T, NAlter);
						(F4, [{"unitOfMeasure", V} | T], Alter) when is_list(V) ->
							{AU, AS} = prod_price_ufm_et(V),
							S = product_size(AU, octets, AS),
							NAlter = Alter#alteration{units = AU, size = S},
							F4(F4, T, NAlter);
						(_, [], Alter) ->
							Alter;
						(_, _, _) ->
							throw(malfored_request)
			end,
			F3 = fun(F3, [{"currencyCode", C} | T], Price) when is_list(C)->
							F3(F3, T, Price#price{currency = C});
						(F3, [{"taxIncludedAmount", A} | T], Price) when is_integer(A) ->
							F3(F3, T, Price#price{amount = A});
						(_, [], Price) ->
							Price;
						(_, _, _) ->
							throw(malfored_request)
			end,
			F2 = fun(F2, [{"name", V} | T], Price) when is_list(V)->
							F2(F2, T, Price#price{name = V});
						(F2, [{"description", V} | T], Price) when is_list(V) ->
							F2(F2, T, Price#price{description = V});
						(F2, [{"priceType", V} | T], Price) when is_list(V) ->
							PT = price_type(V),
							F2(F2, T, Price#price{type = PT});
						(F2, [{"unitOfMeasure", V} | T], Price) when is_list(V) ->
							{U, S} = prod_price_ufm_et(V),
							UP = Price#price{units = U, size = S},
							F2(F2, T, UP);
						(F2, [{"recurringChargePeriod", V} | T], Price) when is_list(V) ->
							RcPeriod = rc_period(V),
							UP = Price#price{period = RcPeriod},
							F2(F2, T, UP);
						(F2, [{"price", {struct, V}} | T], Price) when is_list(V) ->
							UP = F3(F3, V, Price),
							F2(F2, T, UP);
						(F2, [{"prodPriceAlteration", {struct, V}} | T], Price) when is_list(V) ->
							Alter = F4(F4, V, #alteration{}),
							F2(F2, T, Price#price{alteration = Alter});
						(_, [], Price) ->
							Price;
						(_, _, _) ->
							throw(malfored_request)
			end,
			[F2(F2, Obj, #price{}) | Acc]
	end,
	lists:foldl(F, [], Values)
	catch
		_:_ ->
			{error, malfored_request}
	end;
patch_replace1(_, _, _, _) ->
	{error, not_implemented}.
	

