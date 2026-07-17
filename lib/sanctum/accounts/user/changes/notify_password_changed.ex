defmodule Sanctum.Accounts.User.Changes.NotifyPasswordChanged do
  @moduledoc """
  After a successful password change, emails the account owner a security
  notification (`SendPasswordChangedEmail`). Attached to every action that
  writes `hashed_password` on an existing account.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      Sanctum.Accounts.User.Senders.SendPasswordChangedEmail.send(user.email)
      {:ok, user}
    end)
  end
end
