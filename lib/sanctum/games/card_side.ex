defmodule Sanctum.Games.CardSide do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_sides"
    repo Sanctum.Repo

    references do
      # Destroying a card (custom-card deletes especially) takes its sides.
      reference :card, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    # Public card pool browsing: every card face — player *and* encounter —
    # filtered by an advanced search query (see Sanctum.Search; the filter
    # sheet writes the same query syntax). Each side is its own row so
    # multi-sided cards surface every face, and searching an alternate title
    # (e.g. "Peter Parker") ranks that face first. Backs SanctumWeb.CardLive.Pool.
    read :browse do
      argument :query, :string, allow_nil?: true
      argument :scope, :string, allow_nil?: true

      pagination offset?: true, default_limit: 24, countable: true, required?: false

      prepare fn query, context ->
        require Ash.Query

        search = Ash.Query.get_argument(query, :query)
        scope = Ash.Query.get_argument(query, :scope)

        query =
          query
          |> Ash.Query.load(:card)
          # Side `code` sorts by base_code across cards and primary-first within
          # a card (the primary side always holds the smallest code).
          |> Ash.Query.sort(code: :asc)

        # The deckbuilder browses the buildable pool only: aspect + basic
        # player cards, one row per card (primary sides), so a stream keyed
        # by card_id gets no duplicate rows.
        query =
          if scope == "deckbuilding" do
            Ash.Query.filter(
              query,
              ownership in [:player, :basic] and is_primary_side == true
            )
          else
            query
          end

        # Collection status rides the page query as EXISTS subqueries; skipped
        # for anonymous browsing so tiles render no collection UI at all.
        query =
          if context.actor, do: Ash.Query.load(query, :owned), else: query

        if is_binary(search) and String.trim(search) != "" do
          # Bare words search name/subname; `field op value` terms filter
          # any registered card field. Malformed input degrades gracefully
          # (diagnostics are surfaced by the LiveView, not here).
          case Sanctum.Search.compile(search, Sanctum.Search.CardFields) do
            %{expr: nil} -> query
            %{expr: filter} -> Ash.Query.filter(query, ^filter)
          end
        else
          query
        end
      end
    end

    create :create do
      primary? true
      accept [:*]
    end

    update :update do
      primary? true
      accept [:*]
    end

    # Creator-editable homebrew metadata only — never code / side_identifier /
    # is_primary_side / image_url (those are minted or content-addressed).
    # Reached exclusively through Card.update_custom's manage_relationship;
    # the accessing_from policy below keeps direct calls admin-only.
    update :enrich do
      accept [
        :name,
        :subname,
        :ownership,
        :type,
        :aspect,
        :cost,
        :attack,
        :thwart,
        :defense,
        :health,
        :recover,
        :scheme,
        :scheme_star,
        :traits,
        :text,
        :flavor
      ]
    end

    read :primary_sides do
      filter expr(is_primary_side == true)
    end

    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(code == ^arg(:code))
    end

    read :by_codes do
      argument :codes, {:array, :string}, allow_nil?: false
      filter expr(code in ^arg(:codes))
    end

    read :by_card_and_side do
      argument :card_id, :uuid, allow_nil?: false
      argument :side_identifier, :string, allow_nil?: false
      filter expr(card_id == ^arg(:card_id) and side_identifier == ^arg(:side_identifier))
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Mirrors Card's read policy — CardSide is queried directly (:browse,
    # :by_codes) and via load(:card_sides), and Ash applies each resource's
    # own policies on relationship loads, so both resources need the filter.
    # Separate checks on purpose: an expr referencing ^actor(:id) collapses
    # to false wholesale under a nil actor (see Card's read policy).
    policy action_type(:read) do
      authorize_if expr(card.origin == :official)
      authorize_if expr(card.homebrew_project.visibility == :published)
      authorize_if expr(card.homebrew_project.creator_id == ^actor(:id))
    end

    # Catalog mutations are admin-only; system writes (sync, deck import)
    # go through Sanctum.MarvelCdb with authorize?: false. Side writes that
    # arrive through a Card action's manage_relationship (create_custom /
    # the admin *_with_sides actions) are authorized by the Card policy that
    # admitted them.
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
      authorize_if accessing_from(Sanctum.Games.Card, :card_sides)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # Side identification
    attribute :side_identifier, :string, public?: true, allow_nil?: false
    attribute :is_primary_side, :boolean, public?: true, default: false
    attribute :code, :string, public?: true, allow_nil?: false

    # Core card content
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :subname, :string, public?: true
    attribute :traits, {:array, :string}, public?: true, default: []
    attribute :type, Sanctum.Games.CardType, public?: true, allow_nil?: true

    # `ownership` = which pool the card comes from; `aspect` (an aspect key, or
    # nil) is only set for aspect cards. The key references
    # `Sanctum.Games.Aspect` (official keys "aggression"/… plus custom keys);
    # stored as a plain string so unknown/custom aspects never need an enum edit.
    attribute :ownership, Sanctum.Games.CardOwnership, public?: true
    attribute :aspect, :string, public?: true

    attribute :text, :string, public?: true
    attribute :flavor, :string, public?: true

    # Combat stats (structured: value / star / scaling / consequential). An
    # ally's consequential damage lives on the relevant stat, not a separate column.
    attribute :attack, Sanctum.Games.Stat, public?: true
    attribute :thwart, Sanctum.Games.Stat, public?: true
    attribute :defense, Sanctum.Games.Stat, public?: true

    attribute :health, Sanctum.Games.Stat, public?: true

    attribute :cost, :integer, public?: true

    # Icons
    attribute :acceleration_icon, :boolean, public?: true, default: false
    attribute :amplify_icon, :boolean, public?: true, default: false
    attribute :crisis_icon, :boolean, public?: true, default: false
    attribute :hazard_icon, :boolean, public?: true, default: false

    # Resource Fields
    attribute :resource_energy_count, :integer, public?: true
    attribute :resource_physical_count, :integer, public?: true
    attribute :resource_mental_count, :integer, public?: true
    attribute :resource_wild_count, :integer, public?: true

    # Hero Fields
    attribute :hand_size, :integer, public?: true
    attribute :recover, Sanctum.Games.Stat, public?: true

    # Villain Fields (health scaling lives in `health.scaling`)
    attribute :stage, :integer, public?: true
    attribute :scheme, :integer, public?: true
    attribute :scheme_star, :boolean, public?: true, default: false

    # Scheme Fields (structured: value / star / scaling)
    attribute :base_threat, Sanctum.Games.Stat, public?: true
    attribute :escalation_threat, Sanctum.Games.Stat, public?: true
    attribute :max_threat, Sanctum.Games.Stat, public?: true

    # Encounter Fields
    attribute :boost, :integer, public?: true
    attribute :boost_star, :boolean, public?: true, default: false

    # Image
    attribute :image_url, :string, public?: true, allow_nil?: true

    timestamps()
  end

  relationships do
    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end
  end

  calculations do
    # Collection ownership of the canonical card, for the requesting user
    # (nil actor ⇒ false). Lets browse tiles load ownership in the page query.
    calculate :owned, :boolean, expr(card.owned)
  end

  identities do
    identity :unique_card_side, [:card_id, :side_identifier]
    identity :unique_code, [:code]
  end
end
