if Code.ensure_loaded?(Plug) do
  defmodule Guardian.Plug.VerifyCookie do
    @moduledoc """
    Looks for and validates a token found in the request cookies.

    In the case where:

    a. The cookies are not loaded
    b. A token is already found for `:key`

    This plug will not do anything.

    This, like all other Guardian plugs, requires a Guardian pipeline to be setup.
    It requires an implementation module, an error handler and a key.

    These can be set either:

    1. Upstream on the connection with `plug Guardian.Pipeline`
    2. Upstream on the connection with `Guardian.Pipeline.{put_module, put_error_handler, put_key}`
    3. Inline with an option of `:module`, `:error_handler`, `:key`

    If a token is found but is invalid, the error handler will be called with
    `auth_error(conn, {:invalid_token, reason}, opts)`

    Once a token has been found it will be exchanged for an access (default) token.
    This access token will be placed into the session and connection.

    They will be available using `Guardian.Plug.current_claims/2` and `Guardian.Plug.current_token/2`

    Tokens from cookies should be of type `refresh` and have a relatively long life.
    They will be exchanged for `access` tokens (default)

    Options:

    * `:key` - The location of the token (default `:default`)
    * `:exchange_from` - The type of the cookie (default `"refresh"`)
    * `:exchange_to` - The type of token to provide. Defaults to the implementation modules `default_type`
    * `:ttl` - The time to live of the exchanged token. Defaults to configured values.
    """

    import Plug.Conn
    import Guardian.Plug.Keys

    alias Guardian.Plug, as: GPlug
    alias GPlug.Pipeline

    def init(opts), do: opts

    @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
    def call(%{req_cookies: %Plug.Conn.Unfetched{}} = conn, _opts), do: conn

    def call(conn, opts) do
      with nil <- GPlug.current_token(conn, opts),
           {:ok, token} <- find_token_from_cookies(conn, opts),
           module <- Pipeline.fetch_module!(conn, opts),
           key <- storage_key(conn, opts),
           exchange_from <- Keyword.get(opts, :exchange_from, "refresh"),
           default_type <- module.default_token_type(),
           exchange_to <- Keyword.get(opts, :exchange_to, default_type),
           active_session? <- GPlug.session_active?(conn),
           {:ok, _old, {new_t, new_c}} <-
             Guardian.exchange(module, token, exchange_from, exchange_to, opts) do

        conn
        |> GPlug.put_current_token(new_t, key: key)
        |> GPlug.put_current_claims(new_c, key: key)
        |> maybe_put_in_session(active_session?, new_t, opts)
      else
        :no_token_found ->
          conn

        {:error, reason} ->
          conn
          |> Pipeline.fetch_error_handler!(opts)
          |> apply(:auth_error, [conn, {:invalid_token, reason}, opts])
          |> halt()

        _ ->
          conn
      end
    end

    defp find_token_from_cookies(conn, opts) do
      key = conn |> storage_key(opts) |> token_key()
      token = conn.req_cookies[key] || conn.req_cookies[to_string(key)]
      if token, do: {:ok, token}, else: :no_token_found
    end

    defp maybe_put_in_session(conn, false, _, _), do: conn
    defp maybe_put_in_session(conn, true, token, opts) do
      key = conn |> storage_key(opts) |> token_key()
      put_session(conn, key, token)
    end

    defp storage_key(conn, opts), do: Pipeline.fetch_key(conn, opts)
  end
end
