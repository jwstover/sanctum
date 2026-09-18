defmodule SanctumWeb.Api.DeckTTSController do
  @moduledoc """
  Serves the names-only deck payload the TTS importer tile (task #99/#105)
  resolves against Hitch's Marvel Champions mod bags. Reuses `Deck`'s
  existing published-or-owner read policy, so a private deck a non-owner
  requests is simply absent — this returns 404, never 403, to avoid leaking
  which private decks exist.
  """

  use SanctumWeb, :controller

  def show(conn, %{"id" => id}) do
    actor = Ash.PlugHelpers.get_actor(conn)

    case Sanctum.Decks.get_deck(id,
           actor: actor,
           load: [:hero, deck_cards: [card: [:primary_side]]]
         ) do
      {:ok, deck} ->
        render(conn, :show, deck: deck, side_decks: Sanctum.Decks.SideDecks.for_deck(deck))

      {:error, %Ash.Error.Invalid{}} ->
        conn |> put_status(:not_found) |> put_view(json: SanctumWeb.ErrorJSON) |> render(:"404")

      {:error, %Ash.Error.Forbidden{}} ->
        conn |> put_status(:not_found) |> put_view(json: SanctumWeb.ErrorJSON) |> render(:"404")
    end
  end
end
