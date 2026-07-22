defmodule Sanctum.Games.Changes.DeclareAltArt do
  @moduledoc """
  Converts a single-sided custom card into a CardAlt on an official card.

  The card's identity (its `custom-<uuid>` code) and image carry over; the
  Card row and its side — including any enrichment metadata (name, stats,
  traits, text) — are destroyed with it. That loss is accepted: reverting
  yields a plain image-only custom card again.

  The internal destroy runs `authorize?: false`: the action's policy
  (`ActorOwnsSourceCard`) already proved the actor owns the source card's
  project.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      with {:ok, source} <- fetch_card(changeset, :source_card_id, context.actor, :card_sides),
           {:ok, target} <- fetch_card(changeset, :target_card_id, context.actor, []),
           :ok <- validate_declarable(source, target) do
        [side] = source.card_sides

        changeset
        |> Changeset.force_change_attribute(:code, source.code)
        |> Changeset.force_change_attribute(:base_code, source.base_code)
        |> Changeset.force_change_attribute(
          :side_identifier,
          Changeset.get_argument(changeset, :side_identifier)
        )
        |> Changeset.force_change_attribute(:image_url, side.image_url)
        |> Changeset.force_change_attribute(:artist, Changeset.get_argument(changeset, :artist))
        |> Changeset.force_change_attribute(:origin, :custom)
        |> Changeset.force_change_attribute(:card_id, target.id)
        |> Changeset.force_change_attribute(:creator_id, context.actor.id)
        |> Changeset.force_change_attribute(:homebrew_project_id, source.homebrew_project_id)
        |> Changeset.put_context(:declare_source, source)
      else
        {:error, field, message} ->
          Changeset.add_error(changeset, field: field, message: message)
      end
    end)
    |> Changeset.after_action(fn changeset, alt ->
      # The card's side cascades at the DB level (card_sides.card_id FK).
      # TODO(play-slice): a source referenced by DeckCard/GameCard raises a
      # raw FK error here — same caveat as PairCustomCard.
      Ash.destroy!(changeset.context.declare_source,
        action: :destroy_custom,
        authorize?: false
      )

      {:ok, alt}
    end)
  end

  defp fetch_card(changeset, arg, actor, load) do
    # Actor-scoped read: someone else's private custom is simply not found.
    id = Changeset.get_argument(changeset, arg)

    case Ash.get(Sanctum.Games.Card, id, actor: actor, load: load) do
      {:ok, card} -> {:ok, card}
      {:error, _not_found} -> {:error, arg, "card not found"}
    end
  end

  defp validate_declarable(source, target) do
    cond do
      source.origin != :custom ->
        {:error, :source_card_id, "only custom cards can become alternate art"}

      target.origin != :official ->
        {:error, :target_card_id, "alternate art can only target an official card"}

      source.is_multi_sided or length(source.card_sides) != 1 ->
        {:error, :source_card_id, "only a single-sided card can become alternate art"}

      blank_image?(source.card_sides) ->
        {:error, :source_card_id, "the card has no image"}

      true ->
        :ok
    end
  end

  defp blank_image?([side]) do
    is_nil(side.image_url) or side.image_url == ""
  end

  defp blank_image?(_sides), do: true
end
