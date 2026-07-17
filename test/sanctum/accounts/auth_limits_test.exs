defmodule Sanctum.Accounts.AuthLimitsTest do
  # Not async: limits live in a shared ETS table, and the global email
  # budget test manipulates a node-wide counter.
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures

  alias Sanctum.Accounts.AuthLimits
  alias Sanctum.RateLimit

  # Mirror the windows configured in AuthLimits.
  @sign_in_scale :timer.minutes(15)
  @budget_scale :timer.hours(1)

  defp unique_email, do: "limits-#{System.unique_integer([:positive])}@example.com"

  defp drain_budget do
    RateLimit.set(:auth_email_budget, @budget_scale, 1_000)
    on_exit(fn -> RateLimit.set(:auth_email_budget, @budget_scale, 0) end)
  end

  describe "check_sign_in/1" do
    test "allows up to the limit, then denies" do
      email = unique_email()

      for _ <- 1..20 do
        assert AuthLimits.check_sign_in(email) == :ok
      end

      assert AuthLimits.check_sign_in(email) == :rate_limited
    end

    test "keys per normalized email — other emails and case variants share correctly" do
      email = unique_email()
      RateLimit.set({:sign_in, email}, @sign_in_scale, 20)

      assert AuthLimits.check_sign_in(String.upcase(email)) == :rate_limited
      assert AuthLimits.check_sign_in(unique_email()) == :ok
    end
  end

  describe "check_email/2" do
    test "allows 3 per recipient per window, then denies" do
      email = unique_email()

      for _ <- 1..3 do
        assert AuthLimits.check_email(:reset, email) == :ok
      end

      assert AuthLimits.check_email(:reset, email) == :rate_limited
    end

    test "denies once the global budget is exhausted, even for a fresh recipient" do
      drain_budget()

      assert AuthLimits.check_email(:confirmation, unique_email()) == :rate_limited
    end
  end

  describe "sign_in_with_password rate limiting" do
    test "a rate-limited email is rejected before credentials are checked" do
      password = "correctHorse9!"
      email = unique_email()

      Ash.Seed.seed!(Sanctum.Accounts.User, %{
        email: email,
        confirmed_at: DateTime.utc_now(),
        hashed_password: Bcrypt.hash_pwd_salt(password)
      })

      strategy = AshAuthentication.Info.strategy!(Sanctum.Accounts.User, :password)

      # Correct credentials sign in fine below the limit.
      assert {:ok, _user} =
               AshAuthentication.Strategy.action(strategy, :sign_in, %{
                 "email" => email,
                 "password" => password
               })

      # Trip the limiter, then even correct credentials are rejected.
      RateLimit.set({:sign_in, String.downcase(email)}, @sign_in_scale, 1_000)

      assert {:error, %AshAuthentication.Errors.AuthenticationFailed{}} =
               AshAuthentication.Strategy.action(strategy, :sign_in, %{
                 "email" => email,
                 "password" => password
               })
    end
  end

  describe "sender integration" do
    test "reset emails stop after the recipient cap" do
      email = unique_email()
      user = user_fixture(email: email)

      strategy = AshAuthentication.Info.strategy!(Sanctum.Accounts.User, :password)

      # 4 requests: 3 send, the 4th is silently dropped — all return :ok.
      for _ <- 1..4 do
        assert :ok =
                 AshAuthentication.Strategy.action(strategy, :reset_request, %{
                   "email" => to_string(user.email)
                 })
      end

      assert AuthLimits.check_email(:reset, email) == :rate_limited
    end
  end
end
