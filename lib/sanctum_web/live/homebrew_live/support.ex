defmodule SanctumWeb.HomebrewLive.Support do
  @moduledoc """
  Shared homebrew LiveView helpers used by both the project page
  (`HomebrewLive.Show`) and the alt-art wizard (`HomebrewLive.AltArt`) — the
  alt-art list/tile rendering, the official-card target search (also used by
  `HomebrewLive.EditCard`'s declare sheet), and the alt delete handler. Kept in
  one place so the two surfaces can't drift.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]
  import SanctumWeb.Components.CardSideTile, only: [side_view: 2]

  require Ash.Query

  alias Sanctum.Homebrew

  @doc """
  Loads the project's custom alts and assigns `:project_alts` + `:alt_tiles`.
  Expects `:project`, `:current_user`, and `:hero_colors` in assigns.
  """
  def assign_alts(socket) do
    alts = Homebrew.list_project_alts(socket.assigns.project.id, socket.assigns.current_user)
    tiles = Enum.map(alts, &{&1, alt_tile_view(&1, socket.assigns.hero_colors)})

    assign(socket, project_alts: alts, alt_tiles: tiles)
  end

  @doc """
  A view struct for an alt's tile: the targeted official side's real tile with
  the alt's art swapped in — an alt IS the official card wearing different art.
  """
  def alt_tile_view(alt, hero_colors) do
    card = alt.card

    side =
      Enum.find(card.card_sides, &(&1.side_identifier == alt.side_identifier)) ||
        card.primary_side

    %{side_view(%{side | card: card}, hero_colors) | image_url: alt.image_url}
  end

  @doc "Deletes an alt and refreshes the list; flashes the outcome."
  def delete_alt(socket, id) do
    case Homebrew.destroy_alt_art(id, socket.assigns.current_user) do
      :ok -> socket |> assign_alts() |> put_flash(:info, "Alt art deleted.")
      _error -> put_flash(socket, :error, "Could not delete the alt art.")
    end
  end

  @doc """
  Official-card picker results for the alt-art target search: the shared
  `:browse` read (name/subname + query syntax) pinned to the official catalog,
  so the actor's own customs are never targetable. Returns up to 10 `CardSide`s.
  """
  def search_official_sides(q, actor) do
    if is_binary(q) and String.trim(q) != "" do
      Sanctum.Games.CardSide
      |> Ash.Query.for_read(:browse, %{query: q}, actor: actor)
      |> Ash.Query.filter(card.origin == :official)
      |> Ash.read!(actor: actor, page: [limit: 10])
      |> Map.get(:results)
    else
      []
    end
  end
end
