defmodule Sanctum.Accounts.RequestRegistrationTest do
  # Shares the node-wide rate-limit ETS table with other tests.
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures
  import Swoosh.TestAssertions

  alias Sanctum.Accounts.User

  defp unique_email, do: "register-#{System.unique_integer([:positive])}@example.com"

  defp request(email, password, confirmation) do
    User
    |> Ash.ActionInput.for_action(:request_registration, %{
      email: email,
      password: password,
      password_confirmation: confirmation
    })
    |> Ash.run_action(authorize?: false)
  end

  defp get_user(email) do
    User
    |> Ash.Query.for_read(:get_by_email, %{email: email})
    |> Ash.read_one!(authorize?: false)
  end

  test "free email: registers an unconfirmed user and sends the confirmation email" do
    email = unique_email()

    assert :ok = request(email, "goodPassword1!", "goodPassword1!")

    user = get_user(email)
    assert user
    assert user.confirmed_at == nil
    assert user.hashed_password

    assert_email_sent(fn sent ->
      sent.subject == "Confirm your email address" and {"", email} in sent.to
    end)
  end

  test "taken email: creates nothing and sends the already-have-an-account notice" do
    email = unique_email()
    existing = user_fixture(email: email)

    assert :ok = request(email, "attackerPass1!", "attackerPass1!")

    user = get_user(email)
    assert user.id == existing.id
    # The existing account is untouched — no password was set.
    assert user.hashed_password == nil

    assert_email_sent(fn sent ->
      sent.subject == "You already have a Sanctum account" and {"", email} in sent.to
    end)
  end

  test "both outcomes return :ok — the response can't distinguish them" do
    taken = unique_email()
    user_fixture(email: taken)

    assert request(unique_email(), "goodPassword1!", "goodPassword1!") ==
             request(taken, "goodPassword1!", "goodPassword1!")
  end

  test "input problems still error: confirmation mismatch and short password" do
    assert {:error, %Ash.Error.Invalid{}} =
             request(unique_email(), "goodPassword1!", "different1!")

    assert {:error, %Ash.Error.Invalid{}} = request(unique_email(), "short", "short")
  end
end
