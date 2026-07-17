defmodule Sanctum.Accounts.AuthLimits do
  @moduledoc """
  Rate-limit policy for the abuse-exposed authentication surfaces.

  Two things are being protected:

    * **Credentials** — password sign-in attempts are capped per email so a
      targeted brute force gets cut off long before bcrypt's per-attempt cost
      alone would matter. The cap is generous enough that a legitimate user
      fumbling their password never sees it, and it only gates *password*
      sign-in — OAuth and password reset stay available, so this is not an
      account-lockout vector.

    * **The email quota** — auth emails (confirmation, reset) are capped per
      recipient and by a global hourly budget. Resend's free tier is 100
      emails/day; without the budget, anyone hammering the reset form with
      varied addresses could exhaust it and break confirmations for real
      users.

  Every trip emits telemetry (→ Sentry metrics via `Sanctum.Observability`)
  and a throttled `Sentry.capture_message` so alert rules can fire on the
  resulting issues. All checks are ETS-speed and safe to call on the
  request path — they add no measurable timing signal.
  """

  alias Sanctum.RateLimit

  # 20 password attempts per email per 15 minutes.
  @sign_in_scale :timer.minutes(15)
  @sign_in_limit 20

  # 3 auth emails per recipient per hour.
  @recipient_scale :timer.hours(1)
  @recipient_limit 3

  # 30 auth emails total per hour (per node) — quota protection.
  @budget_scale :timer.hours(1)
  @budget_limit 30

  # At most one Sentry event per trip kind per 10 minutes.
  @capture_scale :timer.minutes(10)

  @doc """
  Gate for `sign_in_with_password` attempts. Returns `:ok` or `:rate_limited`.
  """
  @spec check_sign_in(String.t() | Ash.CiString.t()) :: :ok | :rate_limited
  def check_sign_in(email) do
    case RateLimit.hit({:sign_in, normalize(email)}, @sign_in_scale, @sign_in_limit) do
      {:allow, _count} -> :ok
      {:deny, _timeout} -> tripped("sign_in", :warning)
    end
  end

  @doc """
  Gate for outbound auth email (`kind` is `:confirmation` or `:reset`).
  Checks the per-recipient cap, then the global budget — so one hammered
  address can't consume the budget. Returns `:ok` or `:rate_limited`;
  callers skip the send silently on `:rate_limited` so responses look
  identical either way.
  """
  @spec check_email(atom, String.t() | Ash.CiString.t()) :: :ok | :rate_limited
  def check_email(kind, recipient) do
    case RateLimit.hit({:auth_email, normalize(recipient)}, @recipient_scale, @recipient_limit) do
      {:deny, _timeout} ->
        tripped("email_recipient_#{kind}", :warning)

      {:allow, _count} ->
        case RateLimit.hit(:auth_email_budget, @budget_scale, @budget_limit) do
          # Budget exhaustion means auth email is now down for everyone until
          # the window rolls — that's the pager-worthy one.
          {:deny, _timeout} -> tripped("email_budget", :error)
          {:allow, _count} -> :ok
        end
    end
  end

  defp tripped(tag, level) do
    Sanctum.Observability.auth_rate_limited(tag)
    maybe_capture(tag, level)
    :rate_limited
  end

  # One Sentry event per kind per window; the Sentry-side metric still counts
  # every trip. Fingerprinted per kind so each surface groups into its own
  # issue — alert rules key off issue event frequency.
  defp maybe_capture(tag, level) do
    case RateLimit.hit({:sentry_capture, tag}, @capture_scale, 1) do
      {:allow, _} ->
        Sentry.capture_message("Auth rate limit tripped: #{tag}",
          level: level,
          fingerprint: ["auth-rate-limit", tag],
          extra: %{kind: tag}
        )

      {:deny, _} ->
        :ok
    end
  end

  defp normalize(email), do: email |> to_string() |> String.downcase()
end
