defmodule Sanctum.Accounts.User.Actions.RequestRegistration do
  @moduledoc """
  Enumeration-safe registration: succeeds identically whether or not the
  email already has an account, so the register form can never be used to
  probe which emails exist.

    * Email is free — runs `register_with_password`; the confirmation add-on
      emails the confirmation link.
    * Email is taken — no account is touched; the address gets a "you already
      have an account" notice instead. Only the mailbox owner learns which
      case occurred.

  Timing parity: the taken path runs the hash provider's `simulate/0` so it
  costs the same bcrypt work as the real registration's password hash. Both
  emails deliver off the request path (see the senders) and share the same
  rate limits, so neither the response body nor its latency distinguishes
  the cases.

  Input problems that are about the *input* (password too short, confirmation
  mismatch) still surface as form errors — they reveal nothing about accounts.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias Sanctum.Accounts.User

  @impl true
  def run(input, _opts, _context) do
    email = ActionInput.get_argument(input, :email)
    password = ActionInput.get_argument(input, :password)
    confirmation = ActionInput.get_argument(input, :password_confirmation)

    if password == confirmation do
      request(email, password, confirmation)
    else
      {:error,
       Ash.Error.Action.InvalidArgument.exception(
         field: :password_confirmation,
         message: "does not match password"
       )}
    end
  end

  defp request(email, password, confirmation) do
    existing =
      User
      |> Ash.Query.for_read(:get_by_email, %{email: email})
      |> Ash.read_one!(authorize?: false)

    if existing do
      notice_existing(email)
    else
      register(email, password, confirmation)
    end
  end

  defp register(email, password, confirmation) do
    User
    |> Ash.Changeset.for_create(
      :register_with_password,
      %{email: email, password: password, password_confirmation: confirmation},
      authorize?: false
    )
    |> Ash.create()
    |> case do
      {:ok, _user} ->
        :ok

      {:error, error} ->
        # A race on the unique email between our lookup and the insert must
        # not leak either — fold it into the taken path.
        if taken_email_error?(error) do
          notice_existing(email)
        else
          {:error, error}
        end
    end
  end

  defp notice_existing(email) do
    strategy = AshAuthentication.Info.strategy!(User, :password)
    strategy.hash_provider.simulate()

    Sanctum.Accounts.User.Senders.SendRegistrationNoticeEmail.send(email)

    :ok
  end

  defp taken_email_error?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{field: :email} -> true
      %Ash.Error.Changes.InvalidChanges{fields: fields} -> :email in List.wrap(fields)
      _other -> false
    end)
  end

  defp taken_email_error?(_error), do: false
end
