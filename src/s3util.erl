-module(s3util).
-export([get_intval/1, collapse/1, string_join/2, join/1,filter_keyset/2, string_value/1]).

-include_lib("xmerl/include/xmerl.hrl").
-define(S3_CONFIG, [{retries,5}	, {retry_delay,100}, {timeout,5000},{worker,40}]).

get_intval(Key) ->
    ensure_integer(get_val(Key)).

get_val(Key) ->
    case application:get_env(s3erl, Key) of
	{ok,Val} ->
	    Val;
	undefined ->
	    get_default(Key)
    end.

get_default(Key) ->
    case proplists:lookup(Key, ?S3_CONFIG) of
	{Key,Value} ->
	    Value;
	_Else ->
            none
    end.

ensure_integer(Val) ->
    case is_list(Val) of
	true -> list_to_integer(Val);
	false -> Val
    end.

%% Collapse equal keys into one list
consume ({K,V}, [{K,L}|T]) -> [{K,[V|L]}|T];
consume ({K,V}, L) -> [{K,[V]}|L].

collapse (L) ->
    Raw = lists:foldl( fun consume/2, [], L ),
    Ordered = lists:reverse( Raw ),
    lists:keymap( fun lists:sort/1, 2, Ordered ).

%%collapse_empty_test() -> ?assertMatch( [], collapse( [] ) ).
%%collapse_single_test() -> ?assertMatch( [{a,[1]}], collapse( [{a,1}] ) ).
%%collapse_many_test() -> ?assertMatch( [{a,[1,2]},{b,[3]}], collapse( [ {a,1}, {a,2}, {b,3} ] ) ).
%%collapse_order_test() -> ?assertMatch( [{a,[1,2]},{b,[3]}], collapse( [ {a,1}, {a,2}, {b,3} ] ) ).

string_join(Items, Sep) ->
    lists:flatten(lists:reverse(string_join1(Items, Sep, []))).

string_join1([], _Sep, Acc) -> Acc;
string_join1([Head | []], _Sep, Acc) ->
    [Head | Acc];
string_join1([Head | Tail], Sep, Acc) ->
    string_join1(Tail, Sep, [Sep, Head | Acc]).

join ({Key,Values}) ->
    Key ++ ":" ++ string_join(Values,",").

%%join_one_test () -> ?assertMatch( "key:one", join({"key",["one"]} ) ).
%%join_two_test () -> ?assertMatch( "key:one,two", join({"key",["one","two"]} ) ).

filter_keyset (L,KeySet) -> [ {K,V} || {K,V} <- L, lists:member(K,KeySet) ].


						% All the text nodes in an xml doc
string_value( #xmlDocument{ content=Content } ) -> lists:flatten(lists:map( fun string_value/1, Content ));
string_value( #xmlElement{ content=Content } ) -> lists:flatten(lists:map( fun string_value/1, Content ));
string_value( #xmlText{value=Value} ) -> Value;
string_value( [Nodes]) -> lists:flatten(lists:map( fun string_value/1, Nodes ));
string_value( _ ) ->  "".

