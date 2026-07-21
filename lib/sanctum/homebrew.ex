defmodule Sanctum.Homebrew do
  @moduledoc """
  Community custom (homebrew) content: projects and their custom cards.

  A homebrew card is an image plus optional, progressively-added metadata —
  stored in the same `Card`/`CardSide` tables as the official catalog with
  `origin: :custom` and a `HomebrewProject` FK, so browse/search/deckbuilding/
  play work downstream unchanged. Privacy is enforced by filter policies on
  `Card`/`CardSide`/`HomebrewProject`: other users' non-published customs are
  invisible by construction.

  Homebrew writes are always user-scoped through policies — never the
  `authorize?: false` system-write paths used by catalog sync.
  """

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  resources do
    resource Sanctum.Homebrew.HomebrewProject do
      define :create_project, action: :create
      define :update_project, action: :update
      define :set_project_visibility, action: :set_visibility, args: [:visibility]
      define :destroy_project, action: :destroy
      define :get_project, action: :read, get_by: [:id]
      define :list_my_projects, action: :for_creator
    end
  end

  require Ash.Query

  @doc """
  Creates a custom card (with its sides) inside one of the actor's projects.

  `attrs` must include `:homebrew_project_id` and a `:card_sides` list of maps
  — each side needs at least `:image_url` (the image is the card); `:filename`
  seeds the name when none is given. Codes, side identifiers, and origin are
  generated server-side. Goes through policies with the actor — the actor must
  own the target project.
  """
  def create_custom_card(attrs, actor) do
    Sanctum.Games.Card
    |> Ash.Changeset.for_create(:create_custom, attrs, actor: actor)
    |> Ash.create()
  end

  @doc "Custom cards belonging to a project, primary side loaded, oldest first."
  def list_project_cards(project_id, actor) do
    Sanctum.Games.Card
    |> Ash.Query.filter(homebrew_project_id == ^project_id)
    |> Ash.Query.load(:primary_side)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(actor: actor)
  end

  @doc "Destroys one of the actor's custom cards (not-found for anyone else's)."
  def destroy_custom_card(card_id, actor) do
    with {:ok, card} <- Ash.get(Sanctum.Games.Card, card_id, actor: actor) do
      Ash.destroy(card, action: :destroy_custom, actor: actor)
    end
  end

  @doc """
  Enriches one of the actor's custom cards: card-level flags plus per-side
  metadata. `attrs` may include `:card_sides` — a list of maps each carrying
  the side's `:id` plus any enrichable field. Sides omitted from the list are
  untouched; unknown ids are rejected. Nothing is ever required.
  """
  def enrich_custom_card(%Sanctum.Games.Card{} = card, attrs, actor) do
    card
    |> Ash.Changeset.for_update(:update_custom, attrs, actor: actor)
    |> Ash.update()
  end

  def enrich_custom_card(card_id, attrs, actor) do
    with {:ok, card} <- Ash.get(Sanctum.Games.Card, card_id, actor: actor) do
      enrich_custom_card(card, attrs, actor)
    end
  end

  @doc """
  Merges `donor_card_id` into the target card as its back ("b") side — both
  must be single-sided customs in the same project. The donor card row is
  destroyed; its side (and image) live on under the target.
  """
  def pair_custom_cards(target_card_id, donor_card_id, actor) do
    with {:ok, target} <- Ash.get(Sanctum.Games.Card, target_card_id, actor: actor) do
      target
      |> Ash.Changeset.for_update(:pair_custom, %{donor_card_id: donor_card_id}, actor: actor)
      |> Ash.update()
    end
  end

  @doc """
  Splits a two-sided custom card. Returns `{:ok, {updated_card, new_card}}` —
  the original keeps side "a"; side "b" becomes `new_card`'s front.
  """
  def unpair_custom_card(card_id, actor) do
    with {:ok, card} <- Ash.get(Sanctum.Games.Card, card_id, actor: actor),
         {:ok, updated} <-
           card
           |> Ash.Changeset.for_update(:unpair_custom, %{}, actor: actor)
           |> Ash.update() do
      {:ok, {updated, updated.__metadata__.unpaired_card}}
    end
  end
end
