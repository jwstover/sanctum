defmodule Sanctum.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Sanctum.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:sanctum, :token_signing_secret)
  end

  def secret_for([:authentication, :strategies, :google, :client_id], Sanctum.Accounts.User, _, _) do
    Application.fetch_env(:sanctum, :google_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :google, :client_secret],
        Sanctum.Accounts.User,
        _,
        _
      ) do
    Application.fetch_env(:sanctum, :google_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :google, :redirect_uri],
        Sanctum.Accounts.User,
        _,
        _
      ) do
    Application.fetch_env(:sanctum, :google_redirect_uri)
  end
end
