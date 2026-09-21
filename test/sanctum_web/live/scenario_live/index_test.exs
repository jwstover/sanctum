defmodule SanctumWeb.ScenarioLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  defp villain_card!(set, code, stage, image_url) do
    card = create(Sanctum.Games.Card, attrs: %{base_code: code, code: code, set: set.code})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: "Zz Rhino #{stage}",
        type: :villain,
        stage: stage,
        code: code,
        side_identifier: "A",
        is_primary_side: true,
        image_url: image_url
      }
    )

    card
  end

  defp official!(name, opts \\ []) do
    set = villain_set!()

    Enum.each(opts[:cards] || [], fn {code, stage, url} ->
      villain_card!(set, code, stage, url)
    end)

    Sanctum.Games.create_scenario!(
      %{name: name, villain_set_id: set.id, modular_sets: opts[:modular_sets] || []},
      authorize?: false
    )
  end

  defp user_scenario!(name, user, set \\ nil) do
    set = set || villain_set!()
    Sanctum.Games.build_scenario!(%{name: name, villain_set_id: set.id}, actor: user)
  end

  defp modular_set! do
    Sanctum.Catalog.CardSet
    |> Ash.Changeset.for_create(:upsert, %{
      code: "zz_modular",
      name: "Zz Modular",
      set_type: :modular
    })
    |> Ash.create!(authorize?: false)
  end

  test "signed-out visitors can browse official and user scenarios", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})
    modular = modular_set!()

    official =
      official!("Zz Official",
        cards: [{"99001", 1, "https://example.test/rhino1.png"}],
        modular_sets: [modular.id]
      )

    mine = user_scenario!("Zz Mine", owner)

    {:ok, view, html} = live(conn, ~p"/scenarios")
    assert html =~ "Browse Scenarios"

    html = render_async(view)
    assert html =~ "Zz Official"
    assert html =~ "Zz Mine"
    assert html =~ "Official"
    assert html =~ "@zzbrowser"
    assert html =~ "1 modular set"
    assert html =~ "No modular sets"
    assert html =~ "https://example.test/rhino1.png"
    assert has_element?(view, ~s(a[href="/scenarios/#{official.id}"]))
    assert has_element?(view, ~s(a[href="/scenarios/#{mine.id}"]))
    refute html =~ "New Scenario"
  end

  test "a tile shows a plain-text excerpt of the description", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzdesc"})
    s = user_scenario!("Zz Described", owner)

    Sanctum.Games.set_scenario_description!(s, %{description_md: "**Zz bold** notes"},
      actor: owner
    )

    {:ok, view, _} = live(conn, ~p"/scenarios")
    html = render_async(view)
    assert html =~ "Zz bold notes"
    refute html =~ "**Zz bold**"
  end

  test "signed-in users get a New Scenario link", %{conn: conn} do
    conn = log_in_user(conn, Sanctum.AccountsFixtures.user_fixture())
    {:ok, view, _html} = live(conn, ~p"/scenarios")
    assert has_element?(view, ~s(a[href="/scenarios/new"]))
  end

  test "the query narrows the results", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})
    user_scenario!("Zz Alpha", owner)
    user_scenario!("Zz Beta", owner)

    {:ok, view, _} = live(conn, ~p"/scenarios")
    render_async(view)

    view |> form("#scenario-search", %{query: "zz alpha"}) |> render_change()
    html = render_async(view)

    assert html =~ "Zz Alpha"
    refute html =~ "Zz Beta"
  end

  test "sorts by newest and A–Z", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})
    user_scenario!("Zz Alpha", owner)
    user_scenario!("Zz Beta", owner)

    {:ok, view, _} = live(conn, ~p"/scenarios?#{[query: "zz"]}")
    html = render_async(view)
    assert position(html, "Zz Beta") < position(html, "Zz Alpha")

    view |> form("#scenario-filters-form") |> render_change(%{"sort" => "name"})
    assert_patch(view, ~p"/scenarios?#{[query: "zz", sort: "name"]}")
    html = render_async(view)
    assert position(html, "Zz Alpha") < position(html, "Zz Beta")
  end

  test "is:mine and is:official narrow the results", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})
    other = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowseother"})
    official!("Zz Official")
    user_scenario!("Zz Owner Row", owner)
    user_scenario!("Zz Other Row", other)

    {:ok, view, _} = live(log_in_user(conn, owner), ~p"/scenarios?#{[query: "is:mine"]}")
    html = render_async(view)
    assert html =~ "Zz Owner Row"
    refute html =~ "Zz Other Row"
    refute html =~ "Zz Official"

    {:ok, view, _} = live(log_in_user(conn, owner), ~p"/scenarios?#{[query: "is:official"]}")
    html = render_async(view)
    assert html =~ "Zz Official"
    refute html =~ "Zz Owner Row"

    {:ok, view, _} = live(log_in_user(conn, owner), ~p"/scenarios")
    render_async(view)
    view |> form("#scenario-filters-form") |> render_change(%{"is" => ["", "official"]})
    assert_patch(view, ~p"/scenarios?#{[query: "is:official"]}")
  end

  test "signed out, is:mine matches nothing and the sheet hides the Mine chip", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})
    user_scenario!("Zz Owner Row", owner)

    {:ok, view, _} = live(conn, ~p"/scenarios?#{[query: "is:mine"]}")
    html = render_async(view)

    assert html =~ "No scenarios found"
    refute has_element?(view, ~s(#scenario-filters input[name="is[]"][value="mine"]))
    assert has_element?(view, ~s(#scenario-filters input[name="is[]"][value="official"]))
  end

  test "signed in, the sheet offers both flags", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})

    {:ok, view, _} = live(log_in_user(conn, owner), ~p"/scenarios")
    render_async(view)

    assert has_element?(view, ~s(#scenario-filters input[name="is[]"][value="mine"]))
    assert has_element?(view, ~s(#scenario-filters input[name="is[]"][value="official"]))
  end

  test "paginates with infinite scroll", %{conn: conn} do
    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbrowser"})
    set = villain_set!()

    for n <- 1..25 do
      user_scenario!("Zz Page " <> String.pad_leading("#{n}", 2, "0"), owner, set)
    end

    {:ok, view, _} = live(conn, ~p"/scenarios?sort=name")
    html = render_async(view)
    assert html =~ "Zz Page 24"
    refute html =~ "Zz Page 25"
    assert html =~ "25"

    render_hook(view, "next-page", %{})
    assert render_async(view) =~ "Zz Page 25"
  end

  test "an empty catalog says so without offering to clear filters", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/scenarios")
    html = render_async(view)

    assert html =~ "No scenarios yet"
    refute html =~ "Clear filters"
  end

  defp position(html, needle), do: html |> :binary.match(needle) |> elem(0)
end
