defmodule SanctumWeb.HomebrewLive.SetShowNestingTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewSet

  defp set!(project, actor, name, attrs \\ %{}) do
    Homebrew.create_set!(Map.merge(%{homebrew_project_id: project.id, name: name}, attrs),
      actor: actor
    )
  end

  defp card!(set, actor) do
    {:ok, card} =
      Games.create_custom_card(
        %{homebrew_set_id: set.id, card_sides: [%{image_url: "https://img.test/a.png"}]},
        actor: actor
      )

    card
  end

  defp parent_id(set), do: Ash.get!(HomebrewSet, set.id, authorize?: false).parent_set_id
  defp set_id_of(card), do: Ash.get!(Card, card.id, authorize?: false).homebrew_set_id

  # Homebrew is admin-gated at the router for now (see set_show_test.exs).
  # root → child → grandchild, plus a sibling root.
  setup %{conn: conn} do
    creator = admin_user_fixture()
    project = Homebrew.create_project!(%{name: "Test Pack", attestation: true}, actor: creator)
    root = set!(project, creator, "Campaign")
    child = set!(project, creator, "Scenario One", %{parent_set_id: root.id})
    grandchild = set!(project, creator, "Side Scheme", %{parent_set_id: child.id})
    sibling = set!(project, creator, "Loose Set")

    %{
      conn: log_in_user(conn, creator),
      creator: creator,
      project: project,
      root: root,
      child: child,
      grandchild: grandchild,
      sibling: sibling,
      path: fn set -> ~p"/homebrew/#{project.id}/sets/#{set.id}" end
    }
  end

  test "breadcrumbs list the ancestors root-first", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.grandchild))

    crumbs = lv |> element("#set-breadcrumbs") |> render() |> LazyHTML.from_fragment()
    text = LazyHTML.text(crumbs)

    assert text =~ ~r/Test Pack.*Campaign.*Scenario One/s
    refute text =~ "Side Scheme"
  end

  test "child sets render on the parent's page", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.root))

    assert has_element?(lv, "#child-sets #child-set-#{ctx.child.id}", "Scenario One")
    # Direct children only — the grandchild lives on the child's page.
    refute has_element?(lv, "#child-set-#{ctx.grandchild.id}")
  end

  test "the parent picker leaves out the set's own subtree", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.root))

    assert has_element?(lv, "#set-parent-form option[value='#{ctx.sibling.id}']")
    refute has_element?(lv, "#set-parent-form option[value='#{ctx.root.id}']")
    refute has_element?(lv, "#set-parent-form option[value='#{ctx.child.id}']")
    refute has_element?(lv, "#set-parent-form option[value='#{ctx.grandchild.id}']")
  end

  test "a parent can be set and cleared from the page", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.sibling))

    lv |> form("#set-parent-form", %{parent_set_id: ctx.grandchild.id}) |> render_submit()
    assert parent_id(ctx.sibling) == ctx.grandchild.id
    assert lv |> element("#set-breadcrumbs") |> render() =~ "Side Scheme"

    lv |> form("#set-parent-form", %{parent_set_id: ""}) |> render_submit()
    assert is_nil(parent_id(ctx.sibling))
  end

  test "a forged cyclic parent is rejected with a clear message", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.root))

    html = render_submit(lv, "set_parent", %{"parent_set_id" => ctx.grandchild.id})

    assert html =~ "can&#39;t be nested under one of its own child sets"
    assert is_nil(parent_id(ctx.root))
  end

  test "cards move to another set of the project", ctx do
    a = card!(ctx.root, ctx.creator)
    b = card!(ctx.root, ctx.creator)
    stay = card!(ctx.root, ctx.creator)

    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.root))
    lv |> element("button[phx-click='toggle_move_mode']") |> render_click()

    for card <- [a, b] do
      lv
      |> element("button[phx-click='toggle_move_select'][phx-value-id='#{card.id}']")
      |> render_click()
    end

    # Targets are the project's other sets only.
    refute has_element?(lv, "#move-cards-form option[value='#{ctx.root.id}']")

    html =
      lv |> form("#move-cards-form", %{homebrew_set_id: ctx.sibling.id}) |> render_submit()

    assert html =~ "Moved 2 cards to Loose Set."
    assert set_id_of(a) == ctx.sibling.id
    assert set_id_of(b) == ctx.sibling.id
    assert set_id_of(stay) == ctx.root.id
  end

  test "a set from another project is never a move target", ctx do
    card = card!(ctx.root, ctx.creator)
    elsewhere = Homebrew.create_project!(%{name: "Second", attestation: true}, actor: ctx.creator)
    other = set!(elsewhere, ctx.creator, "Elsewhere")

    {:ok, lv, _html} = live(ctx.conn, ctx.path.(ctx.root))
    lv |> element("button[phx-click='toggle_move_mode']") |> render_click()

    lv
    |> element("button[phx-click='toggle_move_select'][phx-value-id='#{card.id}']")
    |> render_click()

    refute has_element?(lv, "#move-cards-form option[value='#{other.id}']")

    # A forged submit is refused too.
    html = render_submit(lv, "move_cards", %{"homebrew_set_id" => other.id})
    assert html =~ "Pick cards and a set to move them to."
    assert set_id_of(card) == ctx.root.id
  end

  test "the project page indents child sets under their parent", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

    assert lv |> element("#set-#{ctx.grandchild.id}") |> render() =~ "margin-left: 3.0rem"
    assert lv |> element("#set-#{ctx.root.id}") |> render() =~ "margin-left: 0"
  end
end
