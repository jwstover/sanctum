defmodule Sanctum.Decks.DeckFavorite do
  @moduledoc """
  A user's personal bookmark of a deck. Favorites are private — visible to and
  writable by their owner only — and work on any deck the user can see (native
  or imported). Backs the `favorited` calculation on `Deck` and the `favorite:`
  search field. A Postgres trigger (see `custom_statements` below) keeps
  `Deck.favorite_count` in sync with this table's rows.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "deck_favorites"
    repo Sanctum.Repo

    references do
      # Drop a user's favorites when the deck goes away (owner deletes a native
      # deck, catalog prune removes an imported one).
      reference :deck, on_delete: :delete
    end

    # The favorite/unfavorite writes and the `favorited` exists-subquery both
    # look up by (user_id, deck_id); the unique identity covers that pair.
    custom_indexes do
      index [:user_id]
    end

    # Keeps decks.favorite_count (Deck's public favorite total) in sync. A
    # trigger rather than an Ash change: the :favorite upsert can't tell an
    # insert from a no-op, unfavorite is a bulk destroy, and deck deletes
    # cascade — a row trigger sees all of them. Raw UPDATEs don't touch
    # decks.updated_at, so the Newest sort isn't reshuffled.
    custom_statements do
      statement :deck_favorite_count_fn do
        after_tables ["decks"]

        up """
        CREATE OR REPLACE FUNCTION deck_favorites_count_trigger() RETURNS trigger AS $$
        BEGIN
          IF TG_OP = 'INSERT' THEN
            UPDATE decks SET favorite_count = favorite_count + 1 WHERE id = NEW.deck_id;
            RETURN NEW;
          ELSE
            UPDATE decks SET favorite_count = GREATEST(favorite_count - 1, 0) WHERE id = OLD.deck_id;
            RETURN OLD;
          END IF;
        END;
        $$ LANGUAGE plpgsql;
        """

        down "DROP FUNCTION IF EXISTS deck_favorites_count_trigger();"
      end

      statement :deck_favorite_count_trigger do
        after_tables ["decks"]

        up """
        CREATE TRIGGER deck_favorites_count
        AFTER INSERT OR DELETE ON deck_favorites
        FOR EACH ROW EXECUTE FUNCTION deck_favorites_count_trigger();
        """

        down "DROP TRIGGER IF EXISTS deck_favorites_count ON deck_favorites;"
      end

      # One-time backfill of the counter from existing favorites.
      statement :deck_favorite_count_backfill do
        after_tables ["decks"]

        up """
        UPDATE decks d SET favorite_count = f.n
        FROM (SELECT deck_id, count(*) AS n FROM deck_favorites GROUP BY deck_id) f
        WHERE d.id = f.deck_id;
        """

        down "SELECT 1;"
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :favorite do
      description "Favorite a deck on the current user's behalf. Idempotent."
      accept [:deck_id]
      change relate_actor(:user)

      # Favoriting the same deck twice is a no-op, not an error.
      upsert? true
      upsert_identity :unique_user_deck
    end
  end

  policies do
    # Favorites are private: a user reads, creates, and destroys only their own.
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:favorite) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :deck, Sanctum.Decks.Deck do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_deck, [:user_id, :deck_id]
  end
end
