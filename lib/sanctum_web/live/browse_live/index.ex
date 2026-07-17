defmodule SanctumWeb.BrowseLive.Index do
  @moduledoc """
  Public content browser — the release taxonomy as Hall-of-Heroes-style waves.

  Top level is waves (Core Set lives in Wave 1); each wave lists its products
  (campaign box, scenario packs, hero packs) as tiles that drill into
  `SanctumWeb.BrowseLive.Show`.
  """
  use SanctumWeb, :live_view

  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias Sanctum.Catalog

  # Product tiles within a wave sort by this rank, then release position.
  @type_rank %{core: 0, campaign_expansion: 1, scenario_pack: 2, hero_pack: 3, promo: 4}

  @type_label %{
    core: "Core Set",
    campaign_expansion: "Campaign Expansion",
    scenario_pack: "Scenario Pack",
    hero_pack: "Hero Pack",
    promo: "Promo"
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Browse")
      # nil until the async load lands — drives the loading/skeleton UI.
      |> assign(:wave_sections, nil)
      |> assign(:other_packs, [])
      |> assign(:covers, %{})
      |> assign(:scroll_restore_pending?, false)

    # Skip every query on the static (disconnected) render; the taxonomy loads
    # asynchronously once the socket connects so nothing blocks first paint.
    socket =
      if connected?(socket), do: start_async(socket, :load_browse, &load_browse/0), else: socket

    {:ok, socket}
  end

  # Pushed by the ScrollRestore hook when the user arrives with a saved scroll
  # position. The page renders asynchronously, so hold the confirmation until
  # the taxonomy load lands and the content exists at its full height.
  @impl true
  def handle_event("restore-scroll", _params, socket) do
    if socket.assigns.wave_sections do
      {:noreply, push_event(socket, "sanctum:scroll-restore", %{})}
    else
      {:noreply, assign(socket, :scroll_restore_pending?, true)}
    end
  end

  @impl true
  def handle_async(:load_browse, {:ok, result}, socket) do
    socket =
      socket
      |> assign(:wave_sections, result.wave_sections)
      |> assign(:other_packs, result.other_packs)
      |> assign(:covers, result.covers)

    socket =
      if socket.assigns.scroll_restore_pending? do
        socket
        |> assign(:scroll_restore_pending?, false)
        |> push_event("sanctum:scroll-restore", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:load_browse, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:wave_sections, [])
     |> put_flash(:error, "Couldn’t load the browser: #{inspect(reason)}")}
  end

  # The full release taxonomy: waves, their packs (with card totals), and one
  # representative cover image per pack.
  defp load_browse do
    waves = Ash.read!(Ash.Query.sort(Catalog.Wave, number: :asc))

    packs =
      Catalog.Pack
      |> Ash.Query.load([:wave, :card_total])
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!()

    by_wave = Enum.group_by(packs, & &1.wave_id)

    wave_sections =
      Enum.map(waves, fn wave ->
        %{wave: wave, packs: sort_packs(Map.get(by_wave, wave.id, []))}
      end)

    %{
      wave_sections: wave_sections,
      # Packs with no wave (e.g. the standalone Ronan Modular Set) render last.
      other_packs: sort_packs(Map.get(by_wave, nil, [])),
      covers: pack_cover_images()
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:browse}>
      <div id="scroll-restore" phx-hook="ScrollRestore"></div>
      <.header>
        Browse
        <:subtitle>
          Every product in the game, organized by release wave — campaign expansions, hero packs, and scenario packs. Pick a product to see everything inside it.
        </:subtitle>
      </.header>

      <!-- first-load skeletons -->
      <div :if={@wave_sections == nil} class="flex flex-col gap-10">
        <section :for={_ <- 1..2}>
          <div class="mb-3.5 h-7 w-48 animate-pulse border-b-2 border-neutral bg-base-300 pb-2"></div>
          <div class="grid grid-cols-2 gap-3.5 sm:grid-cols-[repeat(auto-fill,minmax(220px,1fr))]">
            <div
              :for={_ <- 1..6}
              class="aspect-[3/2] animate-pulse border-2 border-neutral bg-base-300 shadow-comic"
            >
            </div>
          </div>
        </section>
      </div>

      <div :if={@wave_sections != nil} class="flex flex-col gap-10">
        <section :for={section <- @wave_sections} :if={section.packs != []}>
          <.wave_heading wave={section.wave} packs={section.packs} />
          <.pack_grid packs={section.packs} covers={@covers} />
        </section>

        <section :if={@other_packs != []}>
          <h2 class="mb-3.5 font-anton text-[22px] uppercase tracking-[0.03em]">Other</h2>
          <.pack_grid packs={@other_packs} covers={@covers} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :wave, :map, required: true
  attr :packs, :list, required: true

  defp wave_heading(assigns) do
    assigns = assign(assigns, :campaign, campaign_name(assigns.packs))

    ~H"""
    <div class="mb-3.5 flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b-2 border-neutral pb-2">
      <h2 class="font-anton text-[26px] uppercase leading-none tracking-[0.03em] text-primary">
        {@wave.name}
      </h2>
      <span :if={@campaign} class="font-barlow-condensed text-lg uppercase text-base-content/55">
        {@campaign}
      </span>
    </div>
    """
  end

  attr :packs, :list, required: true
  attr :covers, :map, required: true

  defp pack_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-3.5 sm:grid-cols-[repeat(auto-fill,minmax(220px,1fr))]">
      <.link
        :for={pack <- @packs}
        navigate={~p"/browse/#{pack.code}"}
        class="group flex flex-col border-2 border-neutral bg-base-200 shadow-comic transition hover:-translate-y-0.5 hover:shadow-comic-lg"
      >
        <div class="relative aspect-[3/2] overflow-hidden border-b-2 border-neutral bg-black">
          <img
            :if={@covers[pack.id]}
            src={@covers[pack.id]}
            alt={pack.name}
            loading="lazy"
            class="h-full w-full object-cover object-top opacity-90 transition group-hover:opacity-100"
          />
          <div :if={!@covers[pack.id]} class="h-full w-full bg-hatch"></div>
          <span class="absolute left-1.5 top-1.5 border border-neutral bg-base-100/90 px-1.5 py-0.5 font-ibm-mono text-[10px] uppercase tracking-wide text-base-content/70">
            {type_label(pack.product_type)}
          </span>
        </div>
        <div class="flex flex-1 flex-col gap-1 p-2.5">
          <span class="font-anton text-[15px] uppercase leading-tight tracking-[0.02em] group-hover:text-primary">
            {pack.name}
          </span>
          <span class="mt-auto font-ibm-mono text-[11px] text-base-content/45">
            {pack.card_total || 0} cards<span :if={pack.released_on}> · {pack.released_on.year}</span>
          </span>
        </div>
      </.link>
    </div>
    """
  end

  # Sort tiles: product-type rank, then release position.
  defp sort_packs(packs) do
    Enum.sort_by(packs, &{Map.get(@type_rank, &1.product_type, 9), &1.position || 9999})
  end

  # The campaign expansion (if any) names the wave, e.g. "Sinister Motives".
  defp campaign_name(packs) do
    case Enum.find(packs, &(&1.product_type == :campaign_expansion)) do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp type_label(type), do: Map.get(@type_label, type, "Product")

  # One representative primary-side image per pack for the tile cover. A single
  # DISTINCT ON query avoids an N+1 across 60 packs; casting the uuid to text
  # matches the string ids Ash returns.
  defp pack_cover_images do
    from(c in "cards",
      join: cs in "card_sides",
      on: cs.card_id == c.id and cs.is_primary_side == true,
      where: not is_nil(c.pack_id) and not is_nil(cs.image_url),
      distinct: c.pack_id,
      order_by: [asc: c.pack_id, asc: c.code],
      select: {fragment("?::text", c.pack_id), cs.image_url}
    )
    |> Sanctum.Repo.all()
    |> Map.new()
  end
end
