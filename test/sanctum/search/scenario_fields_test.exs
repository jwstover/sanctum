defmodule Sanctum.Search.ScenarioFieldsTest do
  @moduledoc """
  Each scenario search field narrows as expected, run through the real
  `:browse` action so relationship and exists paths hit Postgres; plus
  `:browse` sorting and pagination.
  """

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Catalog.CardSet
  alias Sanctum.Games
  alias Sanctum.Games.Scenario
  alias Sanctum.Search
  alias Sanctum.Search.{Registry, ScenarioFields}

  @marker "Qzscn"

  defp card_set!(attrs) do
    CardSet
    |> Ash.Changeset.for_create(:upsert, attrs)
    |> Ash.create!(authorize?: false)
  end

  defp read_browse(args, opts) do
    Scenario
    |> Ash.Query.for_read(:browse, args, Keyword.take(opts, [:actor]))
    |> Ash.read!(Keyword.put_new(opts, :authorize?, false))
  end

  defp browse(query, opts \\ []) do
    query |> then(&read_browse(%{query: &1}, opts)) |> Enum.map(& &1.name)
  end

  setup do
    rhino = card_set!(%{code: "qz_rhino", name: "#{@marker} Rhino", set_type: :villain})
    other = card_set!(%{code: "qz_other", name: "#{@marker} Other", set_type: :villain})
    bomb = card_set!(%{code: "qz_bomb", name: "#{@marker} Bomb Scare", set_type: :modular})
    owner = user_fixture(%{username: "qzowner"})

    official =
      Games.create_scenario!(
        %{name: "#{@marker} Official", villain_set_id: rhino.id, modular_sets: [bomb.id]},
        authorize?: false
      )

    homebrew =
      Games.build_scenario!(%{name: "#{@marker} Homebrew", villain_set_id: other.id},
        actor: owner
      )

    %{official: official, homebrew: homebrew, owner: owner}
  end

  describe "fields" do
    test "name narrows" do
      assert browse("name:official #{@marker}") == ["#{@marker} Official"]
      assert browse("n:homebrew") == ["#{@marker} Homebrew"]
    end

    test "villain matches the villain set name and code" do
      assert browse(~s(villain:"#{@marker} rhino")) == ["#{@marker} Official"]
      assert browse("villain:qz_rhino") == ["#{@marker} Official"]
    end

    test "set and modular match the modular set name and code" do
      assert browse(~s(set:"bomb scare")) == ["#{@marker} Official"]
      assert browse("modular:qz_bomb") == ["#{@marker} Official"]
      assert browse("-set:qz_bomb #{@marker}") == ["#{@marker} Homebrew"]
    end

    test "a bare word matches name, villain set and modular set" do
      assert browse("bomb scare") == ["#{@marker} Official"]
      assert browse("#{@marker} rhino") == ["#{@marker} Official"]
      assert browse("official #{@marker}") == ["#{@marker} Official"]
    end

    test "is:official and is:mine", %{owner: owner} do
      assert browse("is:official #{@marker}") == ["#{@marker} Official"]
      assert browse("-is:official #{@marker}") == ["#{@marker} Homebrew"]
      assert browse("is:mine #{@marker}", actor: owner) == ["#{@marker} Homebrew"]
      assert browse("is:mine #{@marker}") == []
      assert browse("is:mine #{@marker}", actor: user_fixture()) == []
    end

    test "modular is an alias of set; unknown flags produce diagnostics" do
      assert Registry.lookup(ScenarioFields, "modular").name == "set"
      assert Search.compile("is:sparkly", ScenarioFields).diagnostics != []
    end
  end

  describe ":browse sort and pagination" do
    setup do
      for suffix <- ["B", "C", "A"] do
        Games.create_scenario!(
          %{name: "#{@marker} Sort #{suffix}", villain_set_id: villain_set!().id},
          authorize?: false
        )
      end

      :ok
    end

    defp names(%Ash.Page.Offset{results: results}), do: names(results)
    defp names(list) when is_list(list), do: Enum.map(list, & &1.name)

    test "sort by name" do
      result = read_browse(%{query: "#{@marker} Sort", sort: "name"}, [])
      assert names(result) == for(s <- ["A", "B", "C"], do: "#{@marker} Sort #{s}")
    end

    test "newest is the default" do
      expected = for s <- ["A", "C", "B"], do: "#{@marker} Sort #{s}"

      assert names(read_browse(%{query: "#{@marker} Sort", sort: "newest"}, [])) == expected
      assert names(read_browse(%{query: "#{@marker} Sort"}, [])) == expected
    end

    test "offset pagination with count and loads" do
      args = %{query: "#{@marker} Sort", sort: "name"}

      page1 = read_browse(args, page: [limit: 2, offset: 0, count: true])
      assert %Ash.Page.Offset{count: 3, more?: true} = page1
      assert names(page1) == ["#{@marker} Sort A", "#{@marker} Sort B"]

      page2 = read_browse(args, page: [limit: 2, offset: 2, count: true])
      assert %Ash.Page.Offset{more?: false} = page2
      assert names(page2) == ["#{@marker} Sort C"]

      [first | _] = page1.results
      assert is_integer(first.modular_set_count)
      assert %CardSet{} = first.villain_set

      assert read_browse(args, page: [count: true]).limit == 24
    end
  end
end
