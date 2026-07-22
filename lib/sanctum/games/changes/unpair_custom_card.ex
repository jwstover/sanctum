defmodule Sanctum.Games.Changes.UnpairCustomCard do
  @moduledoc """
  Splits a two-sided custom card: side "b" moves onto a fresh single-sided
  card in the same project (re-lettered as its "a"/primary side, code
  re-minted). The new card rides back to the caller as the `:unpaired_card`
  record metadata. Internal writes are `authorize?: false` — the action's
  policy already proved the actor owns this project.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Sanctum.Games.CustomCode

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      sides =
        changeset.data
        |> Ash.load!(:card_sides, authorize?: false)
        |> Map.fetch!(:card_sides)

      case Enum.find(sides, &(&1.side_identifier == "b")) do
        nil ->
          Changeset.add_error(changeset, field: :id, message: "card is not two-sided")

        side_b ->
          Changeset.put_context(changeset, :unpair_side_b, side_b)
      end
    end)
    |> Changeset.after_action(fn changeset, card ->
      side_b = changeset.context.unpair_side_b
      code = CustomCode.mint()

      # The primary :create (not :create_custom — that demands image maps and
      # re-mints codes). The fresh uuid code can't collide with its upsert
      # identity, so this is a plain insert.
      new_card =
        Sanctum.Games.Card
        |> Changeset.for_create(:create, %{
          origin: :custom,
          homebrew_project_id: card.homebrew_project_id,
          code: code,
          base_code: code,
          is_multi_sided: false,
          deck_limit: card.deck_limit,
          unique: card.unique,
          permanent: card.permanent
        })
        |> Ash.create!(authorize?: false)

      side_b
      |> Changeset.for_update(:update, %{
        card_id: new_card.id,
        side_identifier: "a",
        code: CustomCode.side_code(code, "a"),
        is_primary_side: true
      })
      |> Ash.update!(authorize?: false)

      {:ok, Ash.Resource.put_metadata(card, :unpaired_card, new_card)}
    end)
  end
end
