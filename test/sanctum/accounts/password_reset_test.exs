defmodule Sanctum.Accounts.PasswordResetTest do
  # Shares the node-wide rate-limit ETS table with other tests.
  use Sanctum.DataCase, async: false

  import Swoosh.TestAssertions

  alias AshAuthentication.{Info, Strategy}
  alias Sanctum.Accounts.User

  test "completing a reset sends the password-changed security notification" do
    email = "reset-notify-#{System.unique_integer([:positive])}@example.com"

    user =
      Ash.Seed.seed!(User, %{
        email: email,
        confirmed_at: DateTime.utc_now(),
        hashed_password: Bcrypt.hash_pwd_salt("oldPassword1!")
      })

    strategy = Info.strategy!(User, :password)
    {:ok, token} = AshAuthentication.Strategy.Password.reset_token_for(strategy, user)

    assert {:ok, _user} =
             Strategy.action(strategy, :reset, %{
               "reset_token" => token,
               "password" => "newPassword2!",
               "password_confirmation" => "newPassword2!"
             })

    assert_email_sent(fn sent ->
      sent.subject == "Your Sanctum password was changed" and {"", email} in sent.to
    end)
  end
end
