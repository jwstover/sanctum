defmodule Sanctum.Accounts.UserProfileTest do
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures

  alias Sanctum.Accounts.User

  describe "update_profile username validation" do
    test "accepts valid usernames" do
      user = user_fixture()

      assert {:ok, updated} = claim(user, "Hero_99", actor: user)
      assert to_string(updated.username) == "Hero_99"
    end

    test "rejects invalid usernames" do
      user = user_fixture()

      for bad <- ["ab", String.duplicate("a", 21), "has space", "has-dash", "nö"] do
        assert {:error, %Ash.Error.Invalid{}} = claim(user, bad, actor: user), inspect(bad)
      end
    end

    test "usernames are unique case-insensitively" do
      taken = "Spidey#{System.unique_integer([:positive])}"
      user_fixture(username: taken)
      user = user_fixture()

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               claim(user, String.downcase(taken), actor: user)

      assert %Ash.Error.Changes.InvalidAttribute{
               field: :username,
               message: "has already been taken"
             } = error
    end
  end

  describe "update_profile policy" do
    test "a user can update their own profile" do
      user = user_fixture()

      assert {:ok, _} = claim(user, "own_handle", actor: user)
    end

    test "another user is forbidden" do
      user = user_fixture()
      other = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} = claim(user, "stolen", actor: other)
    end

    test "an anonymous actor is forbidden" do
      user = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} = claim(user, "anon_claim", actor: nil)
    end
  end

  describe "register_with_google avatar seeding" do
    test "seeds avatar_url from the picture claim on first registration" do
      email = "google-#{System.unique_integer([:positive])}@example.com"

      user =
        register_with_google!(
          google_user_info(email, %{"picture" => "https://lh3.googleusercontent.com/a/pic"})
        )

      assert user.avatar_url == "https://lh3.googleusercontent.com/a/pic"
    end

    test "leaves avatar_url nil when there is no picture claim" do
      email = "google-#{System.unique_integer([:positive])}@example.com"

      user = register_with_google!(google_user_info(email))

      assert user.avatar_url == nil
    end

    test "a re-login upsert never overwrites an existing profile" do
      email = "google-#{System.unique_integer([:positive])}@example.com"

      existing =
        user_fixture(
          email: email,
          username: "keeper#{System.unique_integer([:positive])}",
          avatar_url: "https://example.com/chosen.png"
        )

      user =
        register_with_google!(
          google_user_info(email, %{"picture" => "https://lh3.googleusercontent.com/a/other"})
        )

      assert user.id == existing.id
      assert user.username == existing.username
      assert user.avatar_url == "https://example.com/chosen.png"
    end

    test "backfills avatar_url for an existing user without one" do
      email = "google-#{System.unique_integer([:positive])}@example.com"
      existing = user_fixture(email: email)
      assert existing.avatar_url == nil

      user =
        register_with_google!(
          google_user_info(email, %{"picture" => "https://lh3.googleusercontent.com/a/pic"})
        )

      assert user.id == existing.id
      assert user.avatar_url == "https://lh3.googleusercontent.com/a/pic"
    end
  end

  describe "register_with_discord" do
    test "rejects an unverified Discord email" do
      email = "discord-#{System.unique_integer([:positive])}@example.com"

      assert {:error, %Ash.Error.Invalid{}} =
               register_with_discord(discord_user_info(email, %{"email_verified" => false}))
    end

    test "seeds avatar_url from the picture claim on first registration" do
      email = "discord-#{System.unique_integer([:positive])}@example.com"

      {:ok, user} =
        register_with_discord(
          discord_user_info(email, %{"picture" => "https://cdn.discordapp.com/avatars/1/abc"})
        )

      assert user.avatar_url == "https://cdn.discordapp.com/avatars/1/abc"
    end

    test "ignores the hashless picture URL of users without a custom avatar" do
      email = "discord-#{System.unique_integer([:positive])}@example.com"

      {:ok, user} =
        register_with_discord(
          discord_user_info(email, %{"picture" => "https://cdn.discordapp.com/avatars/1/"})
        )

      assert user.avatar_url == nil
    end

    test "backfills avatar_url for an existing user without one" do
      email = "discord-#{System.unique_integer([:positive])}@example.com"
      existing = user_fixture(email: email)
      assert existing.avatar_url == nil

      {:ok, user} =
        register_with_discord(
          discord_user_info(email, %{"picture" => "https://cdn.discordapp.com/avatars/1/abc"})
        )

      assert user.id == existing.id
      assert user.avatar_url == "https://cdn.discordapp.com/avatars/1/abc"
    end

    test "never overwrites an existing avatar" do
      email = "discord-#{System.unique_integer([:positive])}@example.com"
      existing = user_fixture(email: email, avatar_url: "https://example.com/chosen.png")

      {:ok, user} =
        register_with_discord(
          discord_user_info(email, %{"picture" => "https://cdn.discordapp.com/avatars/1/abc"})
        )

      assert user.id == existing.id
      assert user.avatar_url == "https://example.com/chosen.png"
    end
  end

  describe "avatar editing" do
    test "update_avatar accepts a URL in our own bucket and marks it uploaded" do
      user = user_fixture()

      assert {:ok, updated} = Sanctum.Accounts.update_avatar(user, bucket_url(), actor: user)
      assert updated.avatar_url == bucket_url()
      assert updated.avatar_source == :uploaded
    end

    test "update_avatar rejects a URL outside our bucket" do
      user = user_fixture()

      for bad <- [
            "https://evil.example.com/tracker.png",
            "https://sanctum-cards.fly.storage.tigris.dev/cards/01001.png",
            "not a url",
            nil
          ] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Sanctum.Accounts.update_avatar(user, bad, actor: user),
               inspect(bad)
      end
    end

    test "another user cannot change your avatar" do
      user = user_fixture()
      other = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Sanctum.Accounts.update_avatar(user, bucket_url(), actor: other)

      assert {:error, %Ash.Error.Forbidden{}} = Sanctum.Accounts.clear_avatar(user, actor: other)
    end

    test "clear_avatar drops the picture and records the choice" do
      user = user_fixture(avatar_url: "https://lh3.googleusercontent.com/a/pic")

      assert {:ok, updated} = Sanctum.Accounts.clear_avatar(user, actor: user)
      assert updated.avatar_url == nil
      assert updated.avatar_source == :cleared
    end

    test "use_provider_avatar restores the recorded sign-in photo" do
      email = "google-#{System.unique_integer([:positive])}@example.com"
      picture = "https://lh3.googleusercontent.com/a/pic"
      user = register_with_google!(google_user_info(email, %{"picture" => picture}))

      {:ok, user} = Sanctum.Accounts.update_avatar(user, bucket_url(), actor: user)
      assert {:ok, restored} = Sanctum.Accounts.use_provider_avatar(user, actor: user)

      assert restored.avatar_url == picture
      assert restored.avatar_source == :provider
    end

    test "use_provider_avatar errors when no provider photo was ever recorded" do
      user = user_fixture()

      assert {:error, %Ash.Error.Invalid{}} =
               Sanctum.Accounts.use_provider_avatar(user, actor: user)
    end
  end

  describe "avatar_source vs. the OAuth backfill" do
    test "signing in again does not resurrect a cleared avatar" do
      email = "google-#{System.unique_integer([:positive])}@example.com"
      picture = "https://lh3.googleusercontent.com/a/pic"

      # Same `sub` both times — a returning user, not a new identity.
      info = google_user_info(email, %{"picture" => picture})

      user = register_with_google!(info)
      {:ok, _} = Sanctum.Accounts.clear_avatar(user, actor: user)

      user = register_with_google!(info)

      assert user.avatar_url == nil
      assert user.avatar_source == :cleared
    end

    test "signing in again does not replace an uploaded avatar" do
      email = "google-#{System.unique_integer([:positive])}@example.com"
      existing = user_fixture(email: email)
      {:ok, _} = Sanctum.Accounts.update_avatar(existing, bucket_url(), actor: existing)

      user =
        register_with_google!(
          google_user_info(email, %{"picture" => "https://lh3.googleusercontent.com/a/pic"})
        )

      assert user.avatar_url == bucket_url()
      assert user.avatar_source == :uploaded
    end

    test "the provider photo is still recorded while a custom avatar is in use" do
      email = "google-#{System.unique_integer([:positive])}@example.com"
      picture = "https://lh3.googleusercontent.com/a/pic"
      existing = user_fixture(email: email)
      {:ok, _} = Sanctum.Accounts.update_avatar(existing, bucket_url(), actor: existing)

      user = register_with_google!(google_user_info(email, %{"picture" => picture}))

      # Not in use, but available for "use my sign-in photo".
      assert user.avatar_url == bucket_url()
      assert user.provider_avatar_url == picture
    end

    test "a later sign-in updates the recorded provider photo" do
      email = "google-#{System.unique_integer([:positive])}@example.com"
      info = google_user_info(email, %{"picture" => "https://g/old"})

      user = register_with_google!(info)
      {:ok, _} = Sanctum.Accounts.clear_avatar(user, actor: user)

      user = register_with_google!(%{info | "picture" => "https://g/new"})

      assert user.provider_avatar_url == "https://g/new"
    end
  end

  defp bucket_url do
    Sanctum.CardImages.base_url() <> "/avatars/" <> String.duplicate("a", 64) <> ".png"
  end

  defp claim(user, username, opts) do
    user
    |> Ash.Changeset.for_update(:update_profile, %{username: username}, opts)
    |> Ash.update()
  end

  # Minimal Google OpenID user_info: the resolver requires a stable `sub`
  # claim, and a verified email is what lets an email-matched upsert proceed.
  defp google_user_info(email, extra \\ %{}) do
    Map.merge(
      %{
        "sub" => "google-sub-#{System.unique_integer([:positive])}",
        "email" => email,
        "email_verified" => true
      },
      extra
    )
  end

  defp register_with_google!(user_info) do
    User
    |> Ash.Changeset.for_create(:register_with_google, %{
      user_info: user_info,
      oauth_tokens: %{"access_token" => "test-token"}
    })
    |> Ash.create!(authorize?: false)
  end

  # Assent-normalized Discord claims (Assent.Strategy.Discord.normalize/2
  # maps Discord's raw `verified` field to the standard `email_verified`).
  defp discord_user_info(email, extra) do
    Map.merge(
      %{
        "sub" => "discord-sub-#{System.unique_integer([:positive])}",
        "preferred_username" => "champ",
        "email" => email,
        "email_verified" => true
      },
      extra
    )
  end

  defp register_with_discord(user_info) do
    User
    |> Ash.Changeset.for_create(:register_with_discord, %{
      user_info: user_info,
      oauth_tokens: %{"access_token" => "test-token"}
    })
    |> Ash.create(authorize?: false)
  end
end
