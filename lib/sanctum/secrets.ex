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
end
