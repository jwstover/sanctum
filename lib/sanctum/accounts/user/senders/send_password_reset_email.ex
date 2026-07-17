defmodule Sanctum.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender
  use SanctumWeb, :verified_routes

  import Swoosh.Email

  alias Sanctum.Mailer

  @impl true
  def send(user, token, _) do
    # Skipping silently on :rate_limited keeps the response identical — the
    # requester already sees "check your email" either way.
    with :ok <- Sanctum.Accounts.AuthLimits.check_email(:reset, user.email) do
      email =
        new()
        |> from({"Sanctum", "noreply@mail.sanctummc.com"})
        |> to(to_string(user.email))
        |> subject("Reset your password")
        |> html_body(body(token: token))

      # Deliver off the request path: reset requests return :ok whether or not
      # the account exists, so a synchronous send would leak account existence
      # through response timing (the email API call only happens on a match).
      Task.Supervisor.start_child(Sanctum.TaskSupervisor, fn ->
        Mailer.deliver!(email)
        Sanctum.Observability.auth_email_sent(:reset)
      end)
    end

    :ok
  end

  defp body(params) do
    url = url(~p"/password-reset/#{params[:token]}")

    """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    """
  end
end
