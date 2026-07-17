defmodule Sanctum.Accounts.Preparations.RateLimitSignIn do
  @moduledoc """
  Rejects `sign_in_with_password` attempts once `Sanctum.Accounts.AuthLimits`
  trips for the target email. Runs before AshAuthentication's
  `SignInPreparation`, so limited attempts never reach the bcrypt check —
  a brute force can't burn CPU either.

  Also counts every attempt (`Sanctum.Observability.auth_password_attempt/0`):
  the existing `auth.sign_in` success/failure metric only sees flows that pass
  through `AuthController`, and LiveView-validated password failures don't.
  """

  use Ash.Resource.Preparation

  alias Sanctum.Accounts.AuthLimits

  @impl true
  def prepare(query, _opts, _context) do
    Sanctum.Observability.auth_password_attempt()

    email = Ash.Query.get_argument(query, :email)

    case AuthLimits.check_sign_in(email) do
      :ok ->
        query

      :rate_limited ->
        Ash.Query.add_error(
          query,
          AshAuthentication.Errors.AuthenticationFailed.exception(
            query: query,
            caused_by: %{
              module: __MODULE__,
              action: query.action,
              resource: query.resource,
              message: "rate limited"
            }
          )
        )
    end
  end
end
