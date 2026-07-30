defmodule Sanctum.Accounts.UserApiKeyTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Accounts
  alias Sanctum.Accounts.UserApiKey

  require Ash.Query

  @secret "sk-ant-api03-THISisAsecretKEY1234"

  describe "upsert_key" do
    test "stores a key, decrypts on demand, and keeps a hint", %{} do
      user = user_fixture()

      {:ok, row} =
        Accounts.upsert_api_key(
          %{provider: :anthropic, key: @secret, key_hint: "1234"},
          actor: user
        )

      assert row.provider == :anthropic
      assert row.key_hint == "1234"
      assert row.last_validated_at

      # The plaintext key is not present until the `key` calculation is loaded.
      assert %Ash.NotLoaded{} = row.key

      loaded = Ash.load!(row, [:key], actor: user)
      assert loaded.key == @secret
    end

    test "is stored encrypted at rest (ciphertext != plaintext)" do
      user = user_fixture()

      Accounts.upsert_api_key!(
        %{provider: :anthropic, key: @secret, key_hint: "1234"},
        actor: user
      )

      # Read the raw column straight from Postgres, bypassing Ash/cloak.
      %{rows: [[encrypted]]} =
        Sanctum.Repo.query!(
          "SELECT encrypted_key FROM user_api_keys WHERE user_id = $1",
          [Ecto.UUID.dump!(user.id)]
        )

      assert is_binary(encrypted)
      refute encrypted =~ @secret
    end

    test "re-upsert replaces the key in place (one row per provider)" do
      user = user_fixture()

      Accounts.upsert_api_key!(
        %{provider: :anthropic, key: @secret, key_hint: "1234"},
        actor: user
      )

      Accounts.upsert_api_key!(
        %{provider: :anthropic, key: "sk-ant-NEWvalue0000", key_hint: "0000"},
        actor: user
      )

      assert {:ok, row} = Accounts.api_key_for_provider(:anthropic, actor: user)
      assert row.key_hint == "0000"
      assert Ash.load!(row, [:key], actor: user).key == "sk-ant-NEWvalue0000"

      assert 1 =
               UserApiKey
               |> Ash.Query.filter(user_id == ^user.id)
               |> Ash.count!(authorize?: false)
    end
  end

  describe "policy isolation" do
    test "a user cannot read another user's key" do
      owner = user_fixture()
      other = user_fixture()

      Accounts.upsert_api_key!(
        %{provider: :anthropic, key: @secret, key_hint: "1234"},
        actor: owner
      )

      assert {:ok, nil} = Accounts.api_key_for_provider(:anthropic, actor: other)
      assert {:ok, %UserApiKey{}} = Accounts.api_key_for_provider(:anthropic, actor: owner)
    end

    test "an actor-less read sees nothing" do
      owner = user_fixture()

      Accounts.upsert_api_key!(
        %{provider: :anthropic, key: @secret, key_hint: "1234"},
        actor: owner
      )

      assert [] = Ash.read!(UserApiKey)
    end
  end

  describe "destroy" do
    test "removes the caller's key" do
      user = user_fixture()

      row =
        Accounts.upsert_api_key!(
          %{provider: :anthropic, key: @secret, key_hint: "1234"},
          actor: user
        )

      assert :ok = Accounts.destroy_api_key(row, actor: user)
      assert {:ok, nil} = Accounts.api_key_for_provider(:anthropic, actor: user)
    end
  end
end
