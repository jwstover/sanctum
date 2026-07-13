defmodule SanctumWeb.DeckLive.Index do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <.header>
        Listing Decks
        <:subtitle>{length(@decks)} deck(s) — mostly synced from MarvelCDB</:subtitle>
      </.header>

      <div class="w-full flex-1 min-h-0 overflow-auto">
        <.table
          id="decks"
          rows={@decks}
          row_click={fn deck -> JS.navigate(~p"/decks/#{deck}") end}
        >
          <:col :let={deck} label="Title">
            <div class="font-medium">{deck.title}</div>
          </:col>
          <:col :let={deck} label="Hero">{deck.hero && deck.hero.hero_name}</:col>
          <:col :let={deck} label="Aspects">{format_aspects(deck.aspects)}</:col>
          <:col :let={deck} label="Cards">
            {deck.total_card_count || 0} ({deck.card_row_count} unique)
          </:col>
          <:col :let={deck} label="Source">{deck.source}</:col>
          <:col :let={deck} label="MarvelCDB">
            <span :if={deck.mcdb_id}>{deck.mcdb_type}/{deck.mcdb_id}</span>
          </:col>
          <:col :let={deck} label="Author">
            <span :if={deck.mcdb_user}>#{deck.mcdb_user.mcdb_user_id}</span>
          </:col>

          <:action :let={deck}>
            <.link navigate={~p"/decks/#{deck}"}>Show</.link>
          </:action>
        </.table>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Decks")
     |> assign_decks()}
  end

  defp assign_decks(socket) do
    decks =
      Sanctum.Decks.list_decks!(
        actor: socket.assigns[:current_user],
        load: [:hero, :mcdb_user, :card_row_count, :total_card_count],
        query: [sort: [inserted_at: :desc]]
      )

    assign(socket, :decks, decks)
  end

  defp format_aspects([]), do: "basic"
  defp format_aspects(aspects), do: Enum.map_join(aspects, ", ", &to_string/1)
end
