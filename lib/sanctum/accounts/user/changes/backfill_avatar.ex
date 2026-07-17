defmodule Sanctum.Accounts.User.Changes.BackfillAvatar do
  @moduledoc """
  Backfills `avatar_url` from the OAuth provider's `picture` claim after a
  register upsert resolves to an existing user.

  The OAuth register actions use `upsert_fields []`, so the conflict write
  never touches the profile — without this, a password-registered user who
  later signs in with Google/Discord would keep the gradient fallback
  forever. Runs after the action so it only fires once the sign-in has
  actually succeeded, and only fills when `avatar_url` is nil: an avatar the
  user already has is never overwritten.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, user ->
      picture = changeset |> Ash.Changeset.get_argument(:user_info) |> picture_claim()

      if is_nil(user.avatar_url) and not is_nil(picture) do
        user
        |> Ash.Changeset.for_update(:set_avatar, %{avatar_url: picture})
        |> Ash.update(authorize?: false)
      else
        {:ok, user}
      end
    end)
  end

  # Assent normalizes provider avatars to a "picture" claim. Discord's is
  # built by interpolating the avatar hash, so a user without a custom avatar
  # yields a URL ending in "/" — treat that as absent.
  defp picture_claim(%{"picture" => picture}) when is_binary(picture) and picture != "" do
    if String.ends_with?(picture, "/"), do: nil, else: picture
  end

  defp picture_claim(_user_info), do: nil
end
