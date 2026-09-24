defmodule Sanctum.MarvelCdb.AccountLinkTest do
  @moduledoc false

  # async: false — these toggle the global `:marvel_cdb_req_options` env.
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures

  alias Sanctum.Decks
  alias Sanctum.Decks.McdbUser
  alias Sanctum.MarvelCdb.AccountLink
  alias Sanctum.MarvelCdb.Credentials
  alias Sanctum.MarvelCdb.OAuth

  setup do
    original_req = Application.get_env(:sanctum, :marvel_cdb_req_options)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original_req) end)

    %{user: user_fixture(), other: user_fixture()}
  end

  defp stub_decks(decks, status \\ 200) do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(decks)
    end)
  end

  defp future_token(access_token \\ "access-abc") do
    %{
      access_token: access_token,
      refresh_token: "refresh-xyz",
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    }
  end

  defp find_mcdb_user!(mcdb_user_id) do
    require Ash.Query

    McdbUser
    |> Ash.Query.filter(mcdb_user_id == ^mcdb_user_id)
    |> Ash.read_one!(authorize?: false)
  end

  describe "list_decks/1 and owner_id/1" do
    test "a list of decks resolves the single owner id" do
      stub_decks([%{"id" => 1, "user_id" => 4242}, %{"id" => 2, "user_id" => 4242}])

      assert {:ok, [_, _]} = OAuth.list_decks("token")
      assert {:ok, 4242} = OAuth.owner_id("token")
    end

    test "an empty list has no owner" do
      stub_decks([])

      assert {:ok, []} = OAuth.list_decks("token")
      assert {:error, :no_decks} = OAuth.owner_id("token")
    end

    test "a 5xx (MarvelCDB's empty-deck-list quirk) reads as no_decks" do
      stub_decks(%{}, 500)

      assert {:error, {:server_error, 500}} = OAuth.list_decks("token")
      assert {:error, :no_decks} = OAuth.owner_id("token")
    end

    test "a 200 map body (success: false shape) is unexpected" do
      stub_decks(%{"success" => false})

      assert {:error, :unexpected_response} = OAuth.list_decks("token")
    end

    test "several distinct user_ids are ambiguous" do
      stub_decks([%{"id" => 1, "user_id" => 1}, %{"id" => 2, "user_id" => 2}])

      assert {:error, :ambiguous_owner} = OAuth.owner_id("token")
    end

    test "a non-500 error status passes through" do
      stub_decks(%{}, 401)

      assert {:error, {:http_error, 401}} = OAuth.list_decks("token")
    end
  end

  describe "claim/2" do
    test "claims an unclaimed account", %{user: user} do
      assert {:ok, mcdb_user} = AccountLink.claim(user, 4242)
      assert mcdb_user.sanctum_user_id == user.id
    end

    test "claiming twice for the same user is idempotent", %{user: user} do
      assert {:ok, _} = AccountLink.claim(user, 4242)
      assert {:ok, mcdb_user} = AccountLink.claim(user, 4242)
      assert mcdb_user.sanctum_user_id == user.id
    end

    test "refuses to claim an account another user already holds", %{user: user, other: other} do
      assert {:ok, _} = AccountLink.claim(user, 4242)
      assert {:error, :claimed_by_other} = AccountLink.claim(other, 4242)
    end

    test "preserves an existing username", %{user: user} do
      McdbUser
      |> Ash.Changeset.for_create(:create, %{mcdb_user_id: 4242, username: "atom"})
      |> Ash.create!(authorize?: false)

      assert {:ok, mcdb_user} = AccountLink.claim(user, 4242)
      assert mcdb_user.username == "atom"
    end

    test "the policy forbids a direct claim on a record another user holds", %{
      user: user,
      other: other
    } do
      {:ok, mcdb_user} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 4242})
      {:ok, _} = Decks.claim_mcdb_user(mcdb_user, actor: user)

      assert {:error, %Ash.Error.Forbidden{}} = Decks.claim_mcdb_user(mcdb_user, actor: other)
    end

    test "a nil actor is forbidden" do
      {:ok, mcdb_user} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 4242})

      assert {:error, %Ash.Error.Forbidden{}} = Decks.claim_mcdb_user(mcdb_user, actor: nil)
    end

    test "the default create action rejects sanctum_user_id", %{user: user} do
      assert_raise Ash.Error.Invalid, fn ->
        McdbUser
        |> Ash.Changeset.for_create(:create, %{mcdb_user_id: 4242, sanctum_user_id: user.id})
        |> Ash.create!(authorize?: false)
      end
    end
  end

  describe "connect/2" do
    test "links immediately when decks reveal the owner", %{user: user} do
      stub_decks([%{"id" => 1, "user_id" => 4242}])

      assert {:ok, {:linked, mcdb_user}} = AccountLink.connect(user, future_token())
      assert mcdb_user.sanctum_user_id == user.id
      assert Credentials.connected?(user)
    end

    test "stores the credential but leaves it unlinked with no decks", %{user: user} do
      stub_decks([])

      assert {:ok, {:unlinked, :no_decks}} = AccountLink.connect(user, future_token())
      assert Credentials.connected?(user)
    end

    test "stores the credential but leaves it unlinked on a 500", %{user: user} do
      stub_decks(%{}, 500)

      assert {:ok, {:unlinked, :no_decks}} = AccountLink.connect(user, future_token())
      assert Credentials.connected?(user)
    end

    test "refuses without storing a credential when the account is claimed by another", %{
      user: user,
      other: other
    } do
      {:ok, _} = AccountLink.claim(other, 4242)
      stub_decks([%{"id" => 1, "user_id" => 4242}])

      assert {:error, :claimed_by_other} = AccountLink.connect(user, future_token())
      refute Credentials.connected?(user)

      assert find_mcdb_user!(4242).sanctum_user_id == other.id
    end
  end

  describe "link_existing/0" do
    test "links, leaves unlinked, and counts a conflict across several credentials", %{
      user: linkable,
      other: conflicted
    } do
      deckless = user_fixture()
      already_claimed_by = user_fixture()

      {:ok, _} = AccountLink.claim(already_claimed_by, 4242)

      {:ok, _} = Credentials.connect(linkable, future_token("token-linkable"))
      {:ok, _} = Credentials.connect(deckless, future_token("token-deckless"))
      {:ok, _} = Credentials.connect(conflicted, future_token("token-conflicted"))

      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        case Plug.Conn.get_req_header(conn, "authorization") do
          ["Bearer token-linkable"] ->
            conn |> Plug.Conn.put_status(200) |> Req.Test.json([%{"id" => 1, "user_id" => 1111}])

          ["Bearer token-deckless"] ->
            conn |> Plug.Conn.put_status(200) |> Req.Test.json([])

          ["Bearer token-conflicted"] ->
            conn |> Plug.Conn.put_status(200) |> Req.Test.json([%{"id" => 2, "user_id" => 4242}])
        end
      end)

      summary = AccountLink.link_existing()

      assert summary == %{linked: 1, unlinked: 1, conflicts: 1, errors: 0}
      assert find_mcdb_user!(1111).sanctum_user_id == linkable.id
      assert find_mcdb_user!(4242).sanctum_user_id == already_claimed_by.id
    end

    test "uses the already-valid token without refreshing", %{user: user} do
      {:ok, _} = Credentials.connect(user, future_token())

      stub_decks([%{"id" => 1, "user_id" => 4242}])

      summary = AccountLink.link_existing()

      assert summary.linked == 1
    end
  end
end
