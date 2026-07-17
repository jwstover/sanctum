defmodule Sanctum.Accounts.User.Senders.SendPasswordChangedEmail do
  @moduledoc """
  Security notification: tells the account owner their password was just
  changed, so a hijacked reset (or a change they didn't make) doesn't go
  unnoticed. Sent after `reset_password_with_token` and `change_password`.
  """

  use SanctumWeb, :verified_routes

  import Swoosh.Email

  alias Sanctum.Mailer

  def send(email_address) do
    recipient = to_string(email_address)

    with :ok <- Sanctum.Accounts.AuthLimits.check_email(:password_changed, recipient) do
      email =
        new()
        |> from({"Sanctum", "noreply@mail.sanctummc.com"})
        |> to(recipient)
        |> subject("Your Sanctum password was changed")
        |> html_body(body())

      Task.Supervisor.start_child(Sanctum.TaskSupervisor, fn ->
        Mailer.deliver!(email)
        Sanctum.Observability.auth_email_sent(:password_changed)
      end)
    end

    :ok
  end

  defp body do
    """
    <p>The password for your Sanctum account was just changed, and any other
    active sessions were signed out.</p>
    <p>If this was you, there's nothing to do.</p>
    <p>If it wasn't you, someone else may have access to your account —
    <a href="#{url(~p"/reset")}">reset your password</a> now to lock them out.</p>
    """
  end
end
