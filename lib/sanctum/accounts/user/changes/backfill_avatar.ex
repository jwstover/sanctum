defmodule Sanctum.Accounts.User.Changes.BackfillAvatar do
  @moduledoc """
  Records the OAuth provider's `picture` claim after a register upsert resolves
  to an existing user, and adopts it as the avatar when the user hasn't chosen
  one of their own.

  The OAuth register actions use `upsert_fields []`, so the conflict write
  never touches the profile — without this, a password-registered user who
  later signs in with Google/Discord would keep the gradient fallback forever.
  Runs after the action so it only fires once the sign-in has actually
  succeeded.

  `avatar_source` is what keeps a user's choice from being undone here: only
  `:provider` (never chose, or asked for the provider picture) is eligible to
  be filled. `:uploaded` and `:cleared` are left alone. The claim is still
  stored in `provider_avatar_url` either way, so "use my Google photo" can
  restore it later without waiting for another sign-in.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, user ->
      picture = changeset |> Ash.Changeset.get_argument(:user_info) |> picture_claim()

      case updates(user, picture) do
        [] ->
          {:ok, user}

        attrs ->
          user
          |> Ash.Changeset.for_update(:set_avatar, Map.new(attrs))
          |> Ash.update(authorize?: false)
      end
    end)
  end

  defp updates(_user, nil), do: []

  defp updates(user, picture) do
    remember =
      if user.provider_avatar_url == picture, do: [], else: [provider_avatar_url: picture]

    if is_nil(user.avatar_url) and user.avatar_source == :provider,
      do: [{:avatar_url, picture} | remember],
      else: remember
  end

  # Assent normalizes provider avatars to a "picture" claim. Discord's is
  # built by interpolating the avatar hash, so a user without a custom avatar
  # yields a URL ending in "/" — treat that as absent.
  defp picture_claim(%{"picture" => picture}) when is_binary(picture) and picture != "" do
    if String.ends_with?(picture, "/"), do: nil, else: picture
  end

  defp picture_claim(_user_info), do: nil
end
