-type bucket()        :: string().
-type key()           :: string().
-type contenttype()   :: string().
-type body()          :: binary().
-type etag()          :: string().
-type header()        :: {string(), string()}.
-type lhttp_options() :: [{atom(), term()} | {atom(), term(), term()}].

-record(config, {
          access_key,
          secret_access_key,
          endpoint,
          timeout,
          retry_callback,
          max_retries,
          retry_delay,
          max_concurrency,
          max_concurrency_cb,
          post_request_cb,
          return_headers
}).
