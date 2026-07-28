defmodule Sanctum.Games.Changes.CreateCustomAltArt do
  @moduledoc """
  Creates custom alt art for an official card directly from an uploaded image —
  no source card to convert (contrast `DeclareAltArt`, which destroys a
  `Card`/`CardSide` pair). This is the primary alt-art entry: the creation
  wizard uploads an image, the uploader picks the official target card + side,
  and a `CardAlt` is minted straight from that.

  Mints a fresh `custom-<uuid>` code (outside MarvelCDB's numeric space, so it
  can never resolve a deck slot) with `base_code` equal to the code, mirroring
  a fresh custom card. The target card is fetched actor-scoped and must be
  `:official` — someone else's private custom is simply not found, and a custom
  target is rejected. `homebrew_project_id` and `artist` are accepted attributes
  (the `ActorOwnsProject` policy proves ownership of the project on create).
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      target_id = Changeset.get_argument(changeset, :target_card_id)

      with {:ok, target} <- fetch_target(target_id, context.actor),
           :ok <- validate_target(target) do
        code = Sanctum.Games.CustomCode.mint()

        changeset
        |> Changeset.force_change_attribute(:code, code)
        |> Changeset.force_change_attribute(:base_code, code)
        |> Changeset.force_change_attribute(:origin, :custom)
        |> Changeset.force_change_attribute(:card_id, target.id)
        |> Changeset.force_change_attribute(:creator_id, context.actor.id)
        |> Changeset.force_change_attribute(
          :image_url,
          Changeset.get_argument(changeset, :image_url)
        )
        |> Changeset.force_change_attribute(
          :side_identifier,
          Changeset.get_argument(changeset, :side_identifier)
        )
      else
        {:error, field, message} -> Changeset.add_error(changeset, field: field, message: message)
      end
    end)
  end

  defp fetch_target(id, actor) do
    # Actor-scoped read: someone else's private custom is simply not found.
    case Ash.get(Sanctum.Games.Card, id, actor: actor) do
      {:ok, card} -> {:ok, card}
      {:error, _not_found} -> {:error, :target_card_id, "card not found"}
    end
  end

  defp validate_target(%{origin: :official}), do: :ok

  defp validate_target(_target),
    do: {:error, :target_card_id, "alternate art can only target an official card"}
end
