defmodule SanctumWeb.HomebrewLive.PublicSet do
  @moduledoc """
  The shareable, read-only page of a homebrew set at
  `/custom/@username/slug`. Slugs are unique per creator, so the creator's
  handle + slug resolve to exactly one set (`Homebrew.get_set_by_creator_slug/3`).

  Read policies decide visibility: anyone sees a published set, only its
  creator sees a private one. Anything that doesn't resolve — unknown or
  renamed username, unknown slug, a set the viewer may not see — raises the
  Ash not-found error, which ash_phoenix maps to an ordinary 404.
  """

  use SanctumWeb, :live_view

  import SanctumWeb.Components.CardSideTile
  import SanctumWeb.HomebrewComponents

  alias Sanctum.Games
  alias Sanctum.Homebrew

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"username" => username, "slug" => slug}, _session, socket) do
    actor = socket.assigns[:current_user]

    set =
      Homebrew.get_set_by_creator_slug!(username, slug,
        actor: actor,
        load: [:set_kind, :creator]
      )

    hero_colors = Sanctum.Heroes.hero_color_map()

    tiles =
      set.id
      |> Games.list_homebrew_set_cards!(actor: actor)
      |> Enum.map(&side_view(%{&1.primary_side | card: &1}, hero_colors))

    {:ok,
     socket
     |> assign(:page_title, set.name)
     |> assign(:set, set)
     |> assign(:card_tiles, tiles)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>{@set.name}</.header>

      <p class="-mt-3 mb-6 font-barlow-condensed text-base-content/70">
        by <span id="set-creator" class="font-bold">@{to_string(@set.creator.username)}</span>
        <span :if={@set.visibility != :published} id="set-unpublished" class="ml-2 uppercase">
          · {@set.visibility} — only you can see this
        </span>
      </p>

      <.set_details set={@set} />

      <p
        :if={@card_tiles == []}
        id="public-set-empty"
        class="font-barlow-condensed text-base-content/60"
      >
        No cards in this set yet.
      </p>

      <div
        :if={@card_tiles != []}
        id="public-set-cards"
        class="grid grid-cols-1 items-start gap-[18px] pb-28 sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]"
      >
        <.card_side_tile :for={side <- @card_tiles} side={side} size="md" />
      </div>
    </Layouts.app>
    """
  end
end
