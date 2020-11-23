-module(s3_test).
-include_lib("eunit/include/eunit.hrl").

integration_test_() ->
    {foreach,
     fun setup/0, fun teardown/1,
     [
      ?_test(get_put()),
      ?_test(concurrency_limit()),
      ?_test(timeout_retry()),
      ?_test(slow_endpoint()),
      ?_test(permission_denied()),
      ?_test(head_object()),
      ?_test(fold()),
      ?_test(list_objects()),
      ?_test(list_objects_with_details())
      ?_test(signed_url()),
      ?_test(reload_config())
     ]}.

setup() ->
    application:start(asn1),
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    application:start(lhttpc),
    {ok, Pid} = s3_server:start_link(default_config()),
    [Pid].

teardown(Pids) ->
    [begin unlink(P), exit(P, kill) end || P <- Pids].





get_put() ->
    delete_if_existing(bucket(), <<"foo">>),

    ?assertEqual({ok, not_found}, s3:get(bucket(), <<"foo">>)),
    ?assertEqual({ok, not_found}, s3:get(bucket(), "foo")),

    ?assertMatch({ok, _}, s3:put(bucket(), <<"foo">>, <<"bazbar">>, "text/plain")),
    ?assertEqual({ok, <<"bazbar">>}, s3:get(bucket(), <<"foo">>)),

    ?assertMatch({ok, _}, s3:put(bucket(), <<"foo-copy">>, <<>>, "text/plain",
                                 5000, [{"x-amz-copy-source", bucket() ++ "/foo"}])).

permission_denied() ->
    ?assertEqual({error, {"AccessDenied", "Access Denied"}},
                 s3:put("foobar", <<"foo">>, <<"bazbar">>, "text/plain")).

concurrency_limit() ->
    Parent = self(),
    MaxConcurrencyCB = fun (N) -> Parent ! {max_concurrency, N} end,

    s3_server:stop(),
    s3_server:start_link([{max_concurrency_callback, MaxConcurrencyCB},
                          {max_concurrency, 3}] ++ default_config()),

    meck:new(s3_lib),
    GetF = fun (_, _, _, _) -> timer:sleep(50), {ok, <<"bazbar">>} end,
    meck:expect(s3_lib, get, GetF),

    P1 = spawn(fun() -> Parent ! {self(), s3:get(bucket(), <<"foo">>)} end),
    P2 = spawn(fun() -> Parent ! {self(), s3:get(bucket(), <<"foo">>)} end),
    P3 = spawn(fun() -> Parent ! {self(), s3:get(bucket(), <<"foo">>)} end),
    P4 = spawn(fun() -> Parent ! {self(), s3:get(bucket(), <<"foo">>)} end),

    receive M0 -> ?assertEqual({max_concurrency, 3}, M0) end,
    ?assertEqual([{error, max_concurrency},
                  {ok, <<"bazbar">>},
                  {ok, <<"bazbar">>},
                  {ok, <<"bazbar">>}],
                 lists:sort([receive {P, M} -> M  end || P <- [P1,P2,P3,P4]])),

    ?assertEqual({ok, <<"bazbar">>}, s3:get(bucket(), <<"foo">>)),
    ?assertEqual({ok, [{puts, 0}, {gets, 4}, {deletes, 0}, {num_workers, 0}]},
                 s3_server:get_stats()),

    ?assert(meck:validate(s3_lib)),
    meck:unload(s3_lib).

timeout_retry() ->
    Parent = self(),
    RetryCb = fun (Reason, Attempt) ->
                      Parent ! {Reason, Attempt}
              end,
    s3_server:stop(),
    s3_server:start_link([{timeout, 10},
                          {retry_callback, RetryCb},
                          {retry_delay, 10}] ++ default_config()),

    meck:new(lhttpc),
    TimeoutF = fun (_, _, _, _, _) ->
                       timer:sleep(50),
                       {error, timeout}
               end,
    meck:expect(lhttpc, request, TimeoutF),
    %% meck:expect(lhttpc, request, TimeoutF),
    %% meck:expect(lhttpc, request, TimeoutF),

    ?assertEqual({error, timeout}, s3:get(bucket(), <<"foo">>)),

    receive M1 -> ?assertEqual({timeout, 0}, M1) end,
    receive M2 -> ?assertEqual({timeout, 1}, M2) end,
    receive M3 -> ?assertEqual({timeout, 2}, M3) end,
    receive _  -> ?assert(false) after 1 -> ok end,

    ?assert(meck:validate(lhttpc)),
    meck:unload(lhttpc).

slow_endpoint() ->
    Port = webserver:start(gen_tcp, [fun very_slow_response/5]),

    s3_server:stop(),
    s3_server:start_link([{timeout, 10},
                          {endpoint, "localhost:" ++ integer_to_list(Port)},
                          {retry_delay, 10}] ++ default_config()),

    ?assertEqual({error, timeout}, s3:get(bucket(), <<"foo">>, 100)).

head_object() ->
    delete_if_existing(bucket(), "foo"),

    MetaHeader = {"x-amz-meta-foo", "bar"},
    {ok, _} = s3:put(bucket(), "foo", "baz", "text/plain", 5000, [MetaHeader]),

    Result = s3:head(bucket(), "foo"),
    ?assertMatch({ok, _Headers, <<>>}, Result),
    Headers = element(2, Result),
    ?assertEqual("bar", proplists:get_value("X-Amz-Meta-Foo", Headers)).


list_objects() ->
    {ok, _} = s3:put(bucket(), "1/1", "foo", "text/plain"),
    {ok, _} = s3:put(bucket(), "1/2", "foo", "text/plain"),
    {ok, _} = s3:put(bucket(), "1/3", "foo", "text/plain"),
    {ok, _} = s3:put(bucket(), "2/1", "foo", "text/plain"),


    ?assertEqual({ok, [<<"1/1">>, <<"1/2">>, <<"1/3">>]},
                 s3:list(bucket(), "1/", 10, "")),

    ?assertEqual({ok, [<<"1/3">>]},
                 s3:list(bucket(), "1/", 10, "1/2")),

    %% List all, includes keys from other tests.
    ?assertMatch({ok, [<<"1/1">>, <<"1/2">>, <<"1/3">>, <<"2/1">>, _|_]},
                 s3:list(bucket(), "", 10, "")).


list_objects_with_details() ->
    {ok, _} = s3:put(bucket(), "3/1", "foo", "text/plain"),
    {ok, _} = s3:put(bucket(), "3/2", "foo", "text/plain"),
    {ok, _} = s3:put(bucket(), "3/3", "foo", "text/plain"),


    ?assertMatch({ok, [ [{key, <<"3/1">>},
                         {last_modified, _}]
                      , [{key, <<"3/2">>},
                         {last_modified, _}]
                      , [{key, <<"3/3">>},
                         {last_modified, _}]
                      ]
                  },
                 s3:list_details(bucket(), "3/", 10, "")).


fold() ->
    %% Depends on earlier tests to setup data.
    ?assertEqual([<<"1/3">>, <<"1/2">>, <<"1/1">>],
                 s3:fold(bucket(), "1/", fun(Key, Acc) -> [Key|Acc] end, [])),

     %% List all, includes keys from other tests.
    ?assertMatch([<<"1/1">>, <<"1/2">>, <<"1/3">>, <<"2/1">>, _|_],
                 s3:fold(bucket(), "", fun(Key, Acc) -> Acc ++ [Key] end, [])).


callback_test() ->
    application:start(asn1),
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    application:start(lhttpc),

    Parent = self(),
    F = fun (Request, Response, ElapsedUs) ->
                Parent ! {Request, Response, ElapsedUs}
        end,

    {ok, _} = s3_server:start_link([{post_request_callback, F} | credentials()]),


    {ok, _} = s3:put(bucket(), "foo", "bar", "text/plain"),
    {ok, _} = s3:get(bucket(), "foo"),

    receive M1 ->
            fun () ->
                    {Request, Response, _ElapsedUs} = M1,
                    ?assertEqual({put, bucket(), "foo", "bar", "text/plain", []},
                                 Request),
                    ?assertMatch({ok, _}, Response)
            end()
    end,

    receive M2 ->
            fun () ->
                    {Request, Response, _ElapsedUs} = M2,
                    ?assertEqual({get, bucket(), "foo", []}, Request),
                    ?assertEqual({ok, <<"bar">>}, Response)
            end()
    end,

    s3_server:stop().

signed_url() ->
    delete_if_existing(bucket(), <<"foo">>),
    ?assertEqual({ok, not_found}, s3:get(bucket(), <<"foo">>)),
    {ok, _} = s3:put(bucket(), <<"foo">>, <<"signed_test">>, "text/plain"),

    {MegaSeconds, Seconds, _} = os:timestamp(),
    Expires = MegaSeconds * 1000000 + Seconds,
    Url = s3:signed_url(bucket(), <<"foo">>, Expires + 3600),

    ?assertMatch(
       {ok, {{200, _}, _, <<"signed_test">>}},
       lhttpc:request(Url, get, [], [], 5000, [])
      ).

reload_config() ->
    OldConfig = s3_server:get_config(),
    s3_server:reload_config([{max_retries, 5} | default_config()]),
    ?assertNotEqual(OldConfig, s3_server:get_config()).


%%
%% HELPERS
%%

very_slow_response(Module, Socket, _, _, _) ->
    timer:sleep(100),
    Module:send(
      Socket,
      "HTTP/1.1 200 OK\r\n"
      "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
      "Great success!"
    ).

delete_if_existing(Bucket, Key) ->
    case s3:get(Bucket, Key) of
        {ok, not_found} ->
            ok;
        {ok, _Doc} ->
            {ok, _} = s3:delete(Bucket, Key)
    end.

default_config() ->
    credentials().

credentials() ->
    File = filename:join([code:priv_dir(s3erl), "s3_credentials.term"]),
    case file:consult(File) of
        {ok, Cred} ->
            Cred;
        {error, enoent} ->
            throw({error, missing_s3_credentials})
    end.

bucket() ->
    File = filename:join([code:priv_dir(s3erl), "bucket.term"]),
    {ok, Config} = file:consult(File),
    proplists:get_value(bucket, Config).
