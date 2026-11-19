defmodule Sanctum.Homebrew do
  @moduledoc """
  Community custom (homebrew) content: projects (the creator's private
  workspace), the publishable sets inside them, their custom cards, and the
  data-driven set kinds (`SetKind`) a project can extend.

  A homebrew card is an image plus optional, progressively-added metadata —
  stored in the same `Card`/`CardSide` tables as the official catalog with
  `origin: :custom` and a `HomebrewSet` FK (the project is reached through the
  set), so browse/search/deckbuilding/
  play work downstream unchanged. Privacy follows the *set*: filter policies on
  `Card`/`CardSide`/`CardAlt`/`Aspect` hide other users' customs whose set is
  not published, while a `HomebrewProject` is a private workspace readable
  only by its creator.

  Homebrew writes are always user-scoped through policies — never the
  `authorize?: false` system-write paths used by catalog sync.
  """

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  resources do
    resource Sanctum.Homebrew.HomebrewProject do
      define :create_project, action: :create
      define :update_project, action: :update
      define :destroy_project, action: :destroy
      define :get_project, action: :read, get_by: [:id]
      define :list_my_projects, action: :for_creator
    end

    resource Sanctum.Homebrew.HomebrewSet do
      define :create_set, action: :create
      define :update_set, action: :update
      define :set_set_visibility, action: :set_visibility, args: [:visibility]
      define :destroy_set, action: :destroy
      define :get_set, action: :read, get_by: [:id]
      define :list_my_sets, action: :for_creator
      define :list_project_sets, action: :by_project, args: [:homebrew_project_id]
    end

    resource Sanctum.Homebrew.SetKind do
      define :list_set_kinds, action: :read
      define :create_set_kind, action: :create_custom
      define :update_set_kind, action: :update
      define :destroy_set_kind, action: :destroy
    end
  end

  require Ash.Query

  @doc """
  Returns the project's oldest set, creating one (named after the project)
  when it has none. A bridge so uploads
  always have a set until the UI grows a set picker.
  """
  def ensure_project_set(%Sanctum.Homebrew.HomebrewProject{} = project, actor) do
    case list_project_sets!(project.id, actor: actor) do
      [] ->
        create_set!(
          %{homebrew_project_id: project.id, name: project.name},
          actor: actor
        )

      sets ->
        Enum.min_by(sets, & &1.inserted_at, DateTime)
    end
  end

  @doc """
  The kinds a set in `project_id` may use: every official kind plus the
  project's own custom kinds, in display order. (A plain `list_set_kinds`
  read would also surface other projects' kinds used by published sets.)
  """
  def list_project_set_kinds(project_id, actor) do
    Sanctum.Homebrew.SetKind
    |> Ash.Query.filter(origin == :official or homebrew_project_id == ^project_id)
    |> Ash.read!(actor: actor)
  end

  @doc """
  Resolves free kind text — the set page's open kind combobox — to a kind for
  a set in `project_id`. The list only *suggests*, it never constrains:

    * blank → `{:ok, nil}` (unclassified is a valid state);
    * text matching a usable kind's label (case-insensitively) or key →
      that existing kind, so picking a suggestion never duplicates a row;
    * anything else → a newly minted project-scoped custom kind labelled
      with the text. No kind string is rejected: the key is derived from the
      label and falls back to a generated one when the text has no usable
      characters.
  """
  def resolve_set_kind(project_id, text, actor) do
    label = text |> to_string() |> String.trim()

    if label == "" do
      {:ok, nil}
    else
      key = kind_key(label)

      case find_kind(project_id, label, key, actor) do
        %Sanctum.Homebrew.SetKind{} = kind -> {:ok, kind}
        nil -> mint_kind(project_id, label, key, actor)
      end
    end
  end

  defp find_kind(project_id, label, key, actor) do
    kinds = list_project_set_kinds(project_id, actor)
    downcased = String.downcase(label)

    # A project's own kind wins over an official one with the same name.
    Enum.find(kinds, &(&1.origin == :custom and String.downcase(&1.label) == downcased)) ||
      Enum.find(kinds, &(String.downcase(&1.label) == downcased)) ||
      Enum.find(kinds, &(&1.origin == :custom and &1.key == key)) ||
      Enum.find(kinds, &(&1.key == key))
  end

  defp mint_kind(project_id, label, key, actor) do
    case create_set_kind(%{homebrew_project_id: project_id, key: key, label: label},
           actor: actor
         ) do
      {:ok, kind} ->
        {:ok, kind}

      # Lost a race (a double submit) on the per-project key identity: the
      # row now exists, so select it instead of failing.
      {:error, error} ->
        case find_kind(project_id, label, key, actor) do
          nil -> {:error, error}
          kind -> {:ok, kind}
        end
    end
  end

  # SetKind keys must match ~r/\A[a-z0-9][a-z0-9_-]*\z/. Labels like "!!!" or
  # "Ωmega" slugify to nothing; those get a generated key so the text is
  # still accepted as a label.
  defp kind_key(label) do
    slug =
      label
      |> String.normalize(:nfd)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> String.slice(0, 60)
      |> String.trim("_")

    if slug == "", do: "kind_#{System.unique_integer([:positive])}", else: slug
  end

  @doc """
  Edits a set's metadata from the set page form. `params` carries string
  keys: `"name"`, `"description"`, `"banner_url"`, `"tags"` (comma-separated)
  and `"kind"` (free text, see `resolve_set_kind/3`). Runs in one transaction
  so a failed update never leaves a freshly minted kind behind.
  """
  def update_set_metadata(%Sanctum.Homebrew.HomebrewSet{} = set, params, actor) do
    # Ash.transact rolls back on an {:error, _} return and wraps any other
    # return in {:ok, _} — so the success branch yields the bare set.
    Ash.transact([Sanctum.Homebrew.HomebrewSet, Sanctum.Homebrew.SetKind], fn ->
      with {:ok, kind} <- resolve_set_kind(set.homebrew_project_id, params["kind"], actor),
           {:ok, updated} <-
             update_set(
               set,
               %{
                 name: params["name"],
                 description: blank_to_nil(params["description"]),
                 banner_url: blank_to_nil(params["banner_url"]),
                 tags: parse_tags(params["tags"]),
                 set_kind_id: kind && kind.id
               },
               actor: actor,
               load: [:set_kind]
             ) do
        updated
      end
    end)
  end

  @doc "Splits comma-separated tag text into trimmed, unique, non-blank tags."
  def parse_tags(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
  end

  def parse_tags(_text), do: []

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil

  @doc """
  Creates a custom card (with its sides) inside one of the actor's sets.

  `attrs` must include a `:homebrew_set_id` (see `ensure_project_set/2`) and a
  `:card_sides` list of maps
  — each side needs at least `:image_url` (the image is the card); `:filename`
  seeds the name when none is given. Codes, side identifiers, and origin are
  generated server-side. Goes through policies with the actor — the actor must
  own the target set.
  """
  def create_custom_card(attrs, actor) do
    Sanctum.Games.Card
    |> Ash.Changeset.for_create(:create_custom, attrs, actor: actor)
    |> Ash.create()
  end

  @doc "Custom cards in one set, primary side loaded, oldest first."
  def list_set_cards(set_id, actor) do
    Sanctum.Games.Card
    |> Ash.Query.filter(homebrew_set_id == ^set_id)
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

  @doc """
  Creates custom alt art for an official card directly from an uploaded image
  — the primary alt-art entry (the creation wizard). No source card to
  convert: the `CardAlt` is minted straight from `image_url`.

  `attrs` must include `:homebrew_set_id`, `:image_url`, and `:target_card_id`
  (an official card); optional `:side_identifier` (default "a", the target side
  the art depicts) and `:artist`. Goes through policies with the actor — the
  actor must own the target set, and the
  target card must be official.
  """
  def create_alt_art(attrs, actor) do
    Sanctum.Games.CardAlt
    |> Ash.Changeset.for_create(:create_custom, attrs, actor: actor)
    |> Ash.create()
  end

  @doc """
  Declares one of the actor's single-sided custom cards as alternate art for
  an official card. CONVERT semantics: the card row (and its side) is
  destroyed and a CardAlt is minted — enrichment metadata does not survive
  the round trip. Opts: `:artist`, `:side_identifier` (default "a", the
  target side the art depicts).
  """
  def declare_alt_art(source_card_id, target_card_id, opts \\ [], actor) do
    Sanctum.Games.CardAlt
    |> Ash.Changeset.for_create(
      :declare_custom,
      %{
        source_card_id: source_card_id,
        target_card_id: target_card_id,
        artist: opts[:artist],
        side_identifier: opts[:side_identifier] || "a"
      },
      actor: actor
    )
    |> Ash.create()
  end

  @doc """
  Converts a custom alt back into a plain image-only custom card in its
  project. Returns `{:ok, new_card}` (not-found for anyone else's alt).
  """
  def revert_alt_art(alt_id, actor) do
    with {:ok, alt} <- Ash.get(Sanctum.Games.CardAlt, alt_id, actor: actor),
         {:ok, destroyed} <-
           Ash.destroy(alt, action: :revert_custom, actor: actor, return_destroyed?: true) do
      {:ok, destroyed.__metadata__.reverted_card}
    end
  end

  @doc "Deletes one of the actor's custom alts outright (not-found for anyone else's)."
  def destroy_alt_art(alt_id, actor) do
    with {:ok, alt} <- Ash.get(Sanctum.Games.CardAlt, alt_id, actor: actor) do
      Ash.destroy(alt, action: :destroy_custom, actor: actor)
    end
  end

  @doc """
  Custom alts in any of a project's sets, oldest first, with the target card and
  its sides loaded (the project page renders the target side's tile wearing
  the alt's art).
  """
  def list_project_alts(project_id, actor) do
    Sanctum.Games.CardAlt
    |> Ash.Query.filter(homebrew_set.homebrew_project_id == ^project_id)
    |> Ash.Query.load(card: [:card_sides, :primary_side])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(actor: actor)
  end

  @doc """
  Custom alts in one set, oldest first, with the target card and its sides
  loaded (the set page renders the target side's tile wearing the alt's art).
  """
  def list_set_alts(set_id, actor) do
    Sanctum.Games.CardAlt
    |> Ash.Query.filter(homebrew_set_id == ^set_id)
    |> Ash.Query.load(card: [:card_sides, :primary_side])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(actor: actor)
  end
end
