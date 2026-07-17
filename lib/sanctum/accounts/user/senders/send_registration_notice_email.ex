defmodule Sanctum.Accounts.User.Senders.SendRegistrationNoticeEmail do
  @moduledoc """
  Tells an address that a registration was attempted but it already has an
  account. Part of the enumeration-safe register flow: the *form* response is
  identical either way, and this email — visible only to the mailbox owner —
  is where the "you already have an account" truth is allowed to live.
  """

  use SanctumWeb, :verified_routes

  import Swoosh.Email

  alias Sanctum.Mailer

  def send(email_address) do
    recipient = to_string(email_address)

    # Same silent skip as the other auth senders — a hammered address stops
    # receiving mail, the requester sees nothing different.
    with :ok <- Sanctum.Accounts.AuthLimits.check_email(:registration_notice, recipient) do
      email =
        new()
        |> from({"Sanctum", "noreply@mail.sanctummc.com"})
        |> to(recipient)
        |> subject("You already have a Sanctum account")
        |> html_body(body())

      Task.Supervisor.start_child(Sanctum.TaskSupervisor, fn ->
        Mailer.deliver!(email)
        Sanctum.Observability.auth_email_sent(:registration_notice)
      end)
    end

    :ok
  end

  defp body do
    """
    <p>Someone (hopefully you) tried to create a Sanctum account with this
    email address — but it already has one.</p>
    <p><a href="#{url(~p"/sign-in")}">Sign in here</a>. If you want to sign in
    with a password and haven't set one, use
    <a href="#{url(~p"/reset")}">forgot your password</a> to set it.</p>
    <p>If this wasn't you, you can safely ignore this email — nothing has
    changed.</p>
    """
  end
end
