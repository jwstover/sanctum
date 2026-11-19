defmodule SanctumWeb.HomebrewLive.Support do
  @moduledoc """
  Shared homebrew LiveView helpers — the alt-art list/tile rendering and alt
  delete handler (the set page, `HomebrewLive.SetShow`), and the official-card
  target search (the set page's assign sheet and `HomebrewLive.EditCard`'s
  declare sheet). Kept in one place so the surfaces can't drift.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]
  import SanctumWeb.Components.CardSideTile, only: [side_view: 2]

  require Ash.Query

  alias Sanctum.Games

  @doc """
  Renders a set's markdown description to sanitized HTML (MDEx + ammonia,
  as `Sanctum.ReleaseNotes.to_html/1`), or `nil` when blank.
  """
  # sobelow_skip ["XSS.Raw"] — sanitized by MDEx (ammonia) before marking safe.
  def description_html(md) when is_binary(md) do
    if String.trim(md) == "" do
      nil
    else
      md
      |> MDEx.to_html!(
        extension: [strikethrough: true, autolink: true],
        sanitize: MDEx.Document.default_sanitize_options()
      )
      |> Phoenix.HTML.raw()
    end
  end

  def description_html(_md), do: nil

  @doc "A banner URL safe to render as an image source (https only), else nil."
  def banner_src("https://" <> _rest = url), do: url
  def banner_src(_url), do: nil

  @doc """
  Loads the set's custom alts and assigns `:set_alts` + `:alt_tiles`.
  Expects `:set`, `:current_user`, and `:hero_colors` in assigns.
  """
  def assign_alts(socket) do
    alts =
      Games.list_homebrew_set_alts!(socket.assigns.set.id, actor: socket.assigns.current_user)

    tiles = Enum.map(alts, &{&1, alt_tile_view(&1, socket.assigns.hero_colors)})

    assign(socket, set_alts: alts, alt_tiles: tiles)
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
    case Games.destroy_custom_alt(id, actor: socket.assigns.current_user) do
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

  @doc """
  Orders a project's sets as a depth-first tree: `[{set, depth}]`, roots at
  depth 0, siblings oldest first. Presentation only — the sets are already
  loaded; this just lays them out for an indented list. A set whose parent
  isn't in the list (unreadable) is shown as a root.
  """
  def set_tree(sets) do
    ids = MapSet.new(sets, & &1.id)

    children =
      sets
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> Enum.group_by(fn set ->
        if set.parent_set_id in ids, do: set.parent_set_id, else: nil
      end)

    walk_tree(children, nil, 0)
  end

  defp walk_tree(children, parent_id, depth) do
    children
    |> Map.get(parent_id, [])
    |> Enum.flat_map(&[{&1, depth} | walk_tree(children, &1.id, depth + 1)])
  end

  @doc """
  Orders the unordered `HomebrewSet :ancestors` rows into a root-first
  breadcrumb chain, following `parent_set_id` up from `set`.
  """
  def ancestor_chain(set, ancestors) do
    by_id = Map.new(ancestors, &{&1.id, &1})

    set.parent_set_id
    |> Stream.unfold(fn
      nil -> nil
      id -> with %{} = parent <- by_id[id], do: {parent, parent.parent_set_id}
    end)
    |> Enum.reverse()
  end
end
