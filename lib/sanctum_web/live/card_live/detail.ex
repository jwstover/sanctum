defmodule SanctumWeb.CardLive.Detail do
  @moduledoc """
  Public card detail page — every printed face of a card rendered with the
  same dossier tile as the Card Pool, a metadata side panel (pack, release,
  card set, printings), and any alternate printings. Catalog reads are
  unauthenticated; the admin management view lives at `/admin/cards/:id`.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.CardSideTile

  alias Sanctum.Catalog.ProductType

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:cards}>
      <!-- first-load skeleton -->
      <div :if={@card == nil}>
        <div class="mb-6 h-9 w-1/2 max-w-md animate-pulse bg-base-300"></div>
        <.detail_skeleton />
      </div>

      <div :if={@card != nil}>
        <.header>
          {@title}

          <:actions>
            <.back_button fallback={~p"/cards"} />
            <div id="card-nav" phx-hook=".CardNav" class="flex items-center gap-2">
              <.button
                :if={@prev}
                navigate={~p"/cards/#{@prev.id}"}
                replace
                data-card-nav="prev"
                aria-label="Previous card"
                title={"#{card_name(@prev)} (←)"}
              >
                <.icon name="hero-chevron-left" />
              </.button>
              <.button :if={!@prev} disabled aria-label="Previous card">
                <.icon name="hero-chevron-left" />
              </.button>
              <.button
                :if={@next}
                navigate={~p"/cards/#{@next.id}"}
                replace
                data-card-nav="next"
                aria-label="Next card"
                title={"#{card_name(@next)} (→)"}
              >
                <.icon name="hero-chevron-right" />
              </.button>
              <.button :if={!@next} disabled aria-label="Next card">
                <.icon name="hero-chevron-right" />
              </.button>
            </div>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".CardNav">
              // Window-level arrow keys drive prev/next so they work without
              // focusing the buttons. Chorded keys and keystrokes inside form
              // fields (the global search input, etc.) pass through untouched;
              // matches route through the real links so it's plain live
              // navigation.
              export default {
                mounted() {
                  this.onKeydown = (e) => {
                    if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return
                    if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return
                    if (e.target?.closest?.("input, textarea, select, [contenteditable]")) return
                    const dir = e.key === "ArrowLeft" ? "prev" : "next"
                    const link = this.el.querySelector(`[data-card-nav="${dir}"]`)
                    if (link) {
                      e.preventDefault()
                      link.click()
                    }
                  }
                  window.addEventListener("keydown", this.onKeydown)
                },

                destroyed() {
                  window.removeEventListener("keydown", this.onKeydown)
                },
              }
            </script>
            <.button
              :if={@current_user && @current_user.admin}
              variant="primary"
              navigate={~p"/admin/cards/#{@card}"}
            >
              <.icon name="hero-wrench-screwdriver" /> Manage
            </.button>
          </:actions>
        </.header>

        <div class="mx-auto flex max-w-[1240px] flex-col gap-5">
          <!-- card faces + metadata: equal-height columns (grid stretch); the
             last tile grows so the column matches the panel when it's taller -->
          <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_300px]">
            <div class="flex min-w-0 flex-col gap-[18px] lg:[&>*:last-child]:flex-1">
              <.card_side_tile :for={side <- @sides} id={"side-#{side.id}"} side={side} size="lg" />
            </div>

            <!-- metadata side panel -->
            <.panel class="p-4">
              <div class="mb-3 border-b-2 border-neutral pb-2 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
                Card File
              </div>

              <div class="flex flex-col gap-3">
                <div :if={@pack}>
                  <div class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/45">
                    Pack
                  </div>
                  <.link
                    navigate={~p"/browse/#{@pack.code}"}
                    class="mt-0.5 block font-barlow-condensed text-base font-semibold hover:text-primary"
                  >
                    {@pack.name || @pack.code}
                  </.link>
                </div>

                <.meta
                  :if={@pack}
                  label="Product Type"
                  value={ProductType.label(@pack.product_type)}
                />
                <.meta :if={@pack} label="Released" value={format_date(@pack.released_on)} />
                <.meta :if={@pack && @pack.wave} label="Wave" value={@pack.wave.name} />
                <.meta
                  :if={@card.card_set}
                  label="Card Set"
                  value={card_set_label(@card.card_set)}
                />

                <div class="my-1 h-px bg-neutral"></div>

                <div class="grid grid-cols-2 gap-x-4 gap-y-3">
                  <.meta label="Code" value={@card.base_code} />
                  <.meta label="Printings" value={1 + length(@card.alts)} />
                  <.meta label="Deck Limit" value={@card.deck_limit} />
                  <.meta label="Unique" value={yes_no(@card.unique)} />
                  <.meta label="Permanent" value={yes_no(@card.permanent)} />
                  <.meta label="Multi-sided" value={yes_no(@card.is_multi_sided)} />
                </div>

                <div :if={@current_user} class="my-1 h-px bg-neutral"></div>

                <div :if={@current_user}>
                  <div class="mb-1.5 flex items-center justify-between">
                    <div class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/45">
                      Collection
                    </div>
                    <.owned_badge :if={@owned} />
                  </div>

                  <div class="flex flex-col gap-2">
                    <.collection_toggle
                      owned={@owned == true}
                      event="toggle_card_owned"
                      id={@card.id}
                      title={card_toggle_title(@owned, @pack_owned, @pack)}
                      class="w-full justify-center"
                    />
                    <button
                      :if={@pack}
                      phx-click="toggle_pack_owned"
                      phx-value-id={@pack.id}
                      class="cursor-pointer text-left font-barlow-condensed text-xs font-bold uppercase tracking-[0.06em] text-base-content/50 hover:text-primary"
                    >
                      {if @pack_owned,
                        do: "✓ #{@pack.name || @pack.code} in collection — remove",
                        else: "Add #{@pack.name || @pack.code} to collection"}
                    </button>
                  </div>
                </div>

                <div class="my-1 h-px bg-neutral"></div>

                <a
                  href={"https://marvelcdb.com/card/#{@card.code}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center gap-1.5 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-base-content/60 hover:text-primary"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> View on MarvelCDB
                </a>
              </div>
            </.panel>
          </div>

          <!-- alternate printings -->
          <.panel :if={@alts != []} class="p-4">
            <div class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
              Alternate Printings ({length(@alts)})
            </div>
            <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
              <figure :for={alt <- @alts} class="flex flex-col gap-1.5">
                <div class="aspect-[5/7] w-full overflow-hidden border-2 border-neutral shadow-comic">
                  <img
                    :if={alt.image_url}
                    src={alt.image_url}
                    alt={alt.code}
                    loading="lazy"
                    class="h-full w-full object-cover"
                  />
                  <div
                    :if={!alt.image_url}
                    class="bg-card-hatch flex h-full w-full items-center justify-center"
                  >
                    <span class="whitespace-nowrap font-ibm-mono text-xs uppercase tracking-[0.2em] text-white/[0.32]">
                      no scan
                    </span>
                  </div>
                </div>
                <figcaption class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50">
                  {alt.code}<span :if={alt.pack}> · {alt.pack}</span>
                </figcaption>
              </figure>
            </div>
          </.panel>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp meta(assigns) do
    ~H"""
    <div :if={@value not in [nil, ""]}>
      <div class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/45">
        {@label}
      </div>
      <div class="mt-0.5 font-barlow-condensed text-base font-semibold">{@value}</div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Card")
      # nil until the async load lands — drives the loading/skeleton UI.
      |> assign(:title, nil)
      |> assign(:card, nil)
      |> assign(:pack, nil)
      |> assign(:sides, [])
      |> assign(:alts, [])
      |> assign(:prev, nil)
      |> assign(:next, nil)
      |> assign(:owned, nil)
      |> assign(:pack_owned, false)

    actor = socket.assigns[:current_user]

    # Skip the card load on the static render; it runs asynchronously once the
    # socket connects so the shell paints immediately.
    socket =
      if connected?(socket),
        do: start_async(socket, :load_card, fn -> load_card(id, actor) end),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_card, {:ok, {:ok, data}}, socket) do
    {:noreply,
     socket
     |> assign(:page_title, data.title)
     |> assign(:title, data.title)
     |> assign(:card, data.card)
     |> assign(:pack, data.pack)
     |> assign(:sides, data.sides)
     |> assign(:alts, data.alts)
     |> assign(:prev, data.prev)
     |> assign(:next, data.next)
     |> assign(:owned, data.owned)
     |> assign(:pack_owned, data.pack_owned)}
  end

  def handle_async(:load_card, {:ok, :not_found}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Card not found.")
     |> push_navigate(to: ~p"/cards")}
  end

  def handle_async(:load_card, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Couldn’t load card: #{inspect(reason)}")
     |> push_navigate(to: ~p"/cards")}
  end

  @impl true
  def handle_event("toggle_card_owned", _params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    owned = Sanctum.Collections.toggle_card(socket.assigns.card.id, user)
    {:noreply, assign(socket, :owned, owned)}
  end

  def handle_event("toggle_pack_owned", _params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    pack = socket.assigns.pack

    if socket.assigns.pack_owned,
      do: Sanctum.Collections.remove_pack(pack.id, user),
      else: Sanctum.Collections.add_pack!(pack.id, actor: user)

    # Pack membership flips the card's derived ownership; re-resolve it.
    card = Ash.get!(Sanctum.Games.Card, socket.assigns.card.id, actor: user, load: [:owned])

    {:noreply,
     socket
     |> assign(:pack_owned, !socket.assigns.pack_owned)
     |> assign(:owned, card.owned)}
  end

  def handle_event("toggle_" <> _, _params, socket), do: {:noreply, socket}

  # Hover copy for the tri-state toggle: removing a pack-derived card records
  # an exclusion rather than touching the pack.
  defp card_toggle_title(true, true, pack) when not is_nil(pack),
    do: "Mark as missing from your copy of #{pack.name || pack.code}"

  defp card_toggle_title(true, _, _), do: "Remove from collection"
  defp card_toggle_title(_, _, _), do: "Add this card to your collection"

  # Load the card with every face, its alts, and pack metadata, then build the
  # display maps. Returns `:not_found` for an unknown id so handle_async can
  # redirect rather than crash the LiveView.
  defp load_card(id, actor) do
    collection_loads = if actor, do: [:owned, :owned_via_packs], else: []

    case Ash.get(Sanctum.Games.Card, id,
           actor: actor,
           load:
             collection_loads ++ [:card_sides, :primary_side, :alts, :card_set, pack_ref: [:wave]]
         ) do
      {:ok, card} ->
        hero_colors = Sanctum.Heroes.hero_color_map()
        title = (card.primary_side && card.primary_side.name) || card.base_code

        # side_view/2 reads `side.card` for set/gradient data; the sides were
        # loaded through the card, so hand it back rather than re-querying.
        sides =
          card.card_sides
          |> Enum.sort_by(& &1.side_identifier)
          |> Enum.map(&side_view(%{&1 | card: card}, hero_colors))

        # Every alternate printing. MarvelCDB has no scan for many reprints
        # (imagesrc is null there, so our mirrored image_url is too) — those
        # render as placeholders, sorted after the printings that have art.
        # Pack codes resolve to catalog pack names when the pack has been synced.
        pack_names = pack_names(card.alts)

        alts =
          card.alts
          |> Enum.sort_by(&{is_nil(&1.image_url), &1.code})
          |> Enum.map(&%{&1 | pack: Map.get(pack_names, &1.pack, &1.pack)})

        pack_owned =
          actor && card.pack_ref &&
            Sanctum.Collections.pack_owned?(card.pack_ref.id, actor)

        {:ok,
         %{
           title: title,
           card: card,
           pack: card.pack_ref,
           sides: sides,
           alts: alts,
           prev: adjacent_card(card, actor, :prev),
           next: adjacent_card(card, actor, :next),
           owned: actor && card.owned,
           pack_owned: pack_owned == true
         }}

      {:error, _} ->
        :not_found
    end
  end

  # The neighboring catalog entry in card-code order.
  defp adjacent_card(card, actor, direction) do
    query =
      case direction do
        :prev ->
          Sanctum.Games.Card
          |> Ash.Query.filter(code < ^card.code)
          |> Ash.Query.sort(code: :desc)

        :next ->
          Sanctum.Games.Card
          |> Ash.Query.filter(code > ^card.code)
          |> Ash.Query.sort(code: :asc)
      end

    query
    |> Ash.Query.load(:primary_side)
    |> Ash.Query.limit(1)
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, neighbor} -> neighbor
      _ -> nil
    end
  end

  defp card_name(card), do: (card.primary_side && card.primary_side.name) || card.base_code

  # pack code -> pack name for the packs the alternate printings came from.
  defp pack_names([]), do: %{}

  defp pack_names(alts) do
    codes = alts |> Enum.map(& &1.pack) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Sanctum.Catalog.Pack
    |> Ash.Query.filter(code in ^codes)
    |> Ash.read!()
    |> Map.new(fn p -> {p.code, p.name || p.code} end)
  end

  defp card_set_label(%{name: name, set_type: set_type}) do
    type =
      case set_type do
        nil -> nil
        t -> t |> to_string() |> String.replace("_", " ") |> String.capitalize()
      end

    [name, type] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"
end
