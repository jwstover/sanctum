defmodule SanctumWeb.AuthController do
  use SanctumWeb, :controller
  use AshAuthentication.Phoenix.Controller

  # A completed password reset intentionally does NOT start a session: the
  # log_out_everywhere add-on (apply_on_password_change?) revokes every token
  # the moment the password changes, so "signed in" here would be a half-state
  # the next request drops anyway. Land on sign-in with the new password ready.
  def success(conn, {:password, :reset} = activity, _user, _token) do
    Sanctum.Observability.auth_success(activity)

    conn
    |> put_flash(:info, "Your password has been reset. Sign in with your new password.")
    |> redirect(to: ~p"/sign-in")
  end

  def success(conn, activity, user, _token) do
    Sanctum.Observability.auth_success(activity)
    return_to = get_session(conn, :return_to) || ~p"/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    {message, reason_tag} =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          {"""
           You have already signed in another way, but have not confirmed your account.
           You can confirm your account using the link we sent to you, or by resetting your password.
           """, :unconfirmed_user}

        _ ->
          {"Incorrect email or password", :invalid_credentials}
      end

    Sanctum.Observability.auth_failure(activity, reason_tag)

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:sanctum)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
