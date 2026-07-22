defmodule Sanctum.Games.Changes.RevertAltArt do
  @moduledoc """
  Reverts a custom alt into a fresh single-sided custom card in the same
  project — the inverse of `DeclareAltArt`, minus the enrichment metadata
  and artist credit destroyed at declare time (accepted loss). The new card
  rides back on the destroyed alt as `:reverted_card` metadata.

  Internal writes are `authorize?: false` — the action's policy already
  proved the actor owns this alt. The alt's code is reused for the new card:
  declare consumed the card that held it, so the identity slots are free and
  the card keeps a stable identity across declare/revert round trips.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Sanctum.Games.CustomCode

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      # The target card's name seeds the revert name — nicer than "Untitled".
      # authorize?: false is safe: the target is an official card.
      target =
        changeset.data
        |> Ash.load!([card: :primary_side], authorize?: false)
        |> Map.fetch!(:card)

      name = (target.primary_side && target.primary_side.name) || "Untitled"
      Changeset.put_context(changeset, :revert_name, name)
    end)
    |> Changeset.after_action(fn changeset, alt ->
      code = alt.code

      new_card =
        Sanctum.Games.Card
        |> Changeset.for_create(:create, %{
          origin: :custom,
          homebrew_project_id: alt.homebrew_project_id,
          code: code,
          base_code: code,
          is_multi_sided: false
        })
        |> Ash.create!(authorize?: false)

      Sanctum.Games.CardSide
      |> Changeset.for_create(:create, %{
        card_id: new_card.id,
        code: CustomCode.side_code(code, "a"),
        side_identifier: "a",
        is_primary_side: true,
        name: changeset.context.revert_name,
        image_url: alt.image_url
      })
      |> Ash.create!(authorize?: false)

      {:ok, Ash.Resource.put_metadata(alt, :reverted_card, new_card)}
    end)
  end
end
