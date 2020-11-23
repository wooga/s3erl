%% @doc Library for accessing Amazons S3 database.
-module(s3).

-export([get/2, get/3]).
-export([start_stream_get/6, read_stream_response/2, read_stream_body/2]).
-export([put/4, put/5, put/6]).
-export([delete/2, delete/3]).
-export([head/2, head/3, head/4]).
-export([list/4, list/5, list_details/4, list_details/5]).
-export([fold/4]).
-export([stats/0]).
-export([signed_url/3, signed_url/4, signed_url/5]).

%% alternative API with explicit Pid for s3_server
-export([pget/3, pget/4]).
-export([pput/5, pput/6, pput/7]).
-export([pdelete/3, pdelete/4]).
-export([phead/3, phead/4, phead/5]).
-export([plist/5, plist/6, plist_details/5, plist_details/6]).
-export([pfold/5]).
-export([pstats/1]).

-include("../include/s3.hrl").

-export_type([bucket/0]).
-export_type([key/0]).

-type value() :: string() | binary().
-export_type([value/0]).

-type expire() :: pos_integer().
-export_type([expire/0]).

-spec get(Bucket::bucket(), Key::key()) ->
                 {ok, [ResponseHeaders::header()], Body::value()} |
                 {ok, Body::value()} | term().
get(Bucket, Key) ->
    get(Bucket, Key, 5000, [], []).

-spec get(Bucket::bucket(), Key::key(), timeout() | [header()]) ->
                 {ok, [ResponseHeaders::header()], Body::value()} |
                 {ok, Body::value()} | term() |
                 {ok, not_modified}.
get(Bucket, Key, Timeout) when is_integer(Timeout) ->
    get(Bucket, Key, Timeout, [], []);
get(Bucket, Key, Headers) when is_list(Headers) ->
    get(Bucket, Key, 5000, Headers, []).

-spec get(Bucket::bucket(), Key::key(), [header()], timeout(), lhttp_options()) ->
                 {ok, [ResponseHeaders::header()], Body::value()} |
                 {ok, Body::value()} | term() |
                 {ok, not_modified}.
get(Bucket, Key, Timeout, Headers, Options) ->
    pget(s3_server, Bucket, Key, Timeout, Headers, Options).


start_stream_get(Bucket, Key, Timeout, Headers, WindowSize, PartSize) ->
    {ok, Pid} = get(Bucket, Key, Timeout, Headers, [{stream_to, self()},
                                                    {partial_download,
                                                     [{window_size, WindowSize},
                                                      {part_size, PartSize}]}]),
    Pid.

read_stream_response(Pid, Timeout) ->
    receive
        {response, _ReqId, Pid, {ok, {Status, Hdrs, Pid}}} ->
            {ok, Status, Hdrs};
        {response, _ReqId, Pid, R} ->
            R
    after Timeout ->
        {error, timeout}
    end.

read_stream_body(Pid, Timeout) ->
    lhttpc:get_body_part(Pid, Timeout).


put(Bucket, Key, Value, ContentType) ->
    put(Bucket, Key, Value, ContentType, 5000).

put(Bucket, Key, Value, ContentType, Timeout) ->
    put(Bucket, Key, Value, ContentType, Timeout, []).

-spec put(Bucket::bucket(), Key::key(), Value::value(),
          ContentType::string(), timeout(), list(header())) ->
                 {ok, Etag::any()} | ok | any().
put(Bucket, Key, Value, ContentType, Timeout, Headers) ->
    pput(s3_server, Bucket, Key, Value, ContentType, Timeout, Headers).


delete(Bucket, Key) ->
    delete(Bucket, Key, 5000).

delete(Bucket, Key, Timeout) ->
    pdelete(s3_server, Bucket, Key, Timeout).


head(Bucket, Key) -> head(Bucket, Key, []).
head(Bucket, Key, Headers) -> head(Bucket, Key, Headers, 5000).
head(Bucket, Key, Headers, Timeout) ->
    phead(s3_server, Bucket, Key, Headers, Timeout).

list(Bucket, Prefix, MaxKeys, Marker) ->
    list(Bucket, Prefix, MaxKeys, Marker, 5000).

list(Bucket, Prefix, MaxKeys, Marker, Timeout) ->
    plist(s3_server, Bucket, Prefix, MaxKeys, Marker, Timeout).


list_details(Bucket, Prefix, MaxKeys, Marker) ->
    list_details(Bucket, Prefix, MaxKeys, Marker, 5000).

list_details(Bucket, Prefix, MaxKeys, Marker, Timeout) ->
    plist_details(s3_server, Bucket, Prefix, MaxKeys, Marker, Timeout).


-spec fold(Bucket::string(), Prefix::string(),
           FoldFun::fun((Key::string(), Acc::term()) -> NewAcc::term()),
           InitAcc::term()) -> FinalAcc::term().
fold(Bucket, Prefix, F, Acc) ->
    pfold(s3_server, Bucket, Prefix, F, Acc).


stats() -> pstats(s3_server).


-spec signed_url(Bucket::bucket(), Key::key(), Expires::expire()) -> list().
signed_url(Bucket, Key, Expires) ->
    call(s3_server, {request, {signed_url, Bucket, Key, Expires}}, 5000).

-spec signed_url(Bucket::bucket(), Key::key(), Expires::expire(),
                 timeout()) -> list().
signed_url(Bucket, Key, Expires, Timeout) ->
    call(s3_server, {request, {signed_url, Bucket, Key, Expires}}, Timeout).

-spec signed_url(Bucket::bucket(), Key::key(), Expires::expire(),
                 Method::atom(), timeout()) -> list().
signed_url(Bucket, Key, Expires, Method, Timeout) ->
    call(s3_server, {request, {signed_url, Bucket, Key, Method, Expires}}, Timeout).


%%
%% API with explicit Pid for s3_server
%%

-spec pget(Pid::pid(), Bucket::bucket(), Key::key()) ->
                 {ok, [ResponseHeaders::header()], Body::value()} |
                 {ok, Body::value()} | term().
pget(Pid, Bucket, Key) ->
    pget(Pid, Bucket, Key, 5000, [], []).

-spec pget(Pid::pid(), Bucket::bucket(), Key::key(), timeout() | [header()]) ->
                 {ok, [ResponseHeaders::header()], Body::value()} |
                 {ok, Body::value()} | term() |
                 {ok, not_modified}.
pget(Pid, Bucket, Key, Timeout) when is_integer(Timeout) ->
    pget(Pid, Bucket, Key, Timeout, [], []);
pget(Pid, Bucket, Key, Headers) when is_list(Headers) ->
    pget(Pid, Bucket, Key, 5000, Headers, []).

-spec pget(Pid::pid(), Bucket::bucket(), Key::key(), [header()], timeout(),
          lhttp_options()) ->
                 {ok, [ResponseHeaders::header()], Body::value()} |
                 {ok, Body::value()} | term() |
                 {ok, not_modified}.
pget(Pid, Bucket, Key, Timeout, Headers, Options) ->
    call(Pid, {request, {get, Bucket, Key, Headers, Options}}, Timeout).


pput(Pid, Bucket, Key, Value, ContentType) ->
    pput(Pid, Bucket, Key, Value, ContentType, 5000).

pput(Pid, Bucket, Key, Value, ContentType, Timeout) ->
    pput(Pid, Bucket, Key, Value, ContentType, Timeout, []).

-spec pput(Pid::pid(), Bucket::bucket(), Key::key(), Value::value(),
          ContentType::string(), timeout(), list(header())) ->
                 {ok, Etag::any()} | ok | any().
pput(Pid, Bucket, Key, Value, ContentType, Timeout, Headers) ->
    call(Pid, {request, {put, Bucket, Key, Value, ContentType, Headers}}, Timeout).


pdelete(Pid, Bucket, Key) ->
    pdelete(Pid, Bucket, Key, 5000).

pdelete(Pid, Bucket, Key, Timeout) ->
    call(Pid, {request, {delete, Bucket, Key}}, Timeout).


phead(Pid, Bucket, Key) -> phead(Pid, Bucket, Key, []).
phead(Pid, Bucket, Key, Headers) -> phead(Pid, Bucket, Key, Headers, 5000).
phead(Pid, Bucket, Key, Headers, Timeout) ->
    call(Pid, {request, {head, Bucket, Key, Headers}}, Timeout).

plist(Pid, Bucket, Prefix, MaxKeys, Marker) ->
    plist(Pid, Bucket, Prefix, MaxKeys, Marker, 5000).

plist(Pid, Bucket, Prefix, MaxKeys, Marker, Timeout) ->
    call(Pid, {request, {list, Bucket, Prefix, integer_to_list(MaxKeys), Marker}},
         Timeout).

plist_details(Pid, Bucket, Prefix, MaxKeys, Marker) ->
    plist_details(Pid, Bucket, Prefix, MaxKeys, Marker, 5000).

plist_details(Pid, Bucket, Prefix, MaxKeys, Marker, Timeout) ->
    call(Pid, {request, {list_details, Bucket, Prefix, integer_to_list(MaxKeys), Marker}}, Timeout).


-spec pfold(Pid::pid(), Bucket::string(), Prefix::string(),
           FoldFun::fun((Key::string(), Acc::term()) -> NewAcc::term()),
           InitAcc::term()) -> FinalAcc::term().
pfold(Pid, Bucket, Prefix, F, Acc) ->
    case s3:plist(Pid, Bucket, Prefix, 100, "") of
        {ok, Keys} when is_list(Keys) ->
            do_fold(Pid, Bucket, Prefix, F, Keys, Acc);
        %% we only expect an error on the first call to list.
        {ok, not_found} -> {error, not_found};
        {error, Rsn} -> {error, Rsn}
    end.

pstats(Pid) -> call(Pid, get_stats, 5000).


%%
%% Internal Helpers
%%

do_fold(Pid, Bucket, Prefix, F, [Last], Acc) ->
    NewAcc = F(Last, Acc),
    %% get next part of the keys from the backup
    {ok, Keys} = plist(Pid, Bucket, Prefix, 100, Last),
    do_fold(Pid, Bucket, Prefix, F, Keys, NewAcc);
do_fold(Pid, Bucket, Prefix, F, [H|T], Acc) ->
    %% this is the normal (recursive) case.
    do_fold(Pid, Bucket, Prefix, F, T, F(H, Acc));
do_fold(_Pid, _Bucket, _Prefix, _F, [], Acc) -> Acc. %% done


call(Pid, Request, Timeout) ->
    gen_server:call(Pid, Request, Timeout).
