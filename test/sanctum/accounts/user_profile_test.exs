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
end
