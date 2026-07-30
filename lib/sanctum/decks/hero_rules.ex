defmodule Sanctum.Decks.HeroRules do
  @moduledoc """
  Explicit deckbuilding exceptions for the handful of heroes whose *aspect and
  copy* rules break the standard template (one aspect, up to 3 copies / 1 if
  unique).

  This is deliberately **not** a general rules engine — the exceptions are
  bespoke text printed on each identity card and aren't exposed as structured
  MarvelCDB data, so there is nothing to derive. Each special hero is spelled
  out by hand, keyed by its `set`. Every other hero uses `standard/0`.

  Scope note: this module covers only deckbuilding *restrictions* (which
  aspects, how many copies). Two other hero quirks are handled elsewhere
  because they aren't deckbuilding rules:

    * **Side decks** (Doctor Strange's Invocation deck, Storm's Weather deck)
      are a separate deck-structure feature, not an aspect/copy restriction.
    * **Split identities** (SP//dr: SP//dr Suit + Peni Parker across two cards)
      are an identity-structure quirk; the deckbuilder simply doesn't require
      the hero and alter-ego sides to live on one card.

  Fields:

    * `max_aspects` — aspects the deck may draw from without it being "off"
      (Spider-Woman: 2, Adam Warlock: 4; standard: 1).
    * `equal_aspects` — the chosen aspects must contribute equal card counts
      (Spider-Woman's Double Agent, Adam Warlock).
    * `single_copy` — every player/basic card is limited to a single copy
      (Adam Warlock).
    * `off_aspect_allowance` — a spec (or `nil`) for cards the deck may include
      from aspects *other* than its one chosen aspect. Several heroes share this
      shape — off-aspect cards matching a trait and type, up to some limit — so
      each fills in its own spec rather than getting a bespoke code path:

          %{
            types: [:ally],      # allowed card types (required)
            traits: ["X-Men"],   # optional; match ANY (period/case-insensitive).
                                 #   omit for a type-only allowance
            resource: :energy,   # optional; require this printed resource pip
                                 #   (:energy | :physical | :mental | :wild)
            limit: 6 | nil,      # nil = unlimited
            limit_by: :copies | :titles,  # default :copies
            label: "X-Men allies"         # for the advisory message
          }

      Gamora: up to 6 attack/thwart events. Cyclops: unlimited X-Men allies.
      Maria Hill: up to 3 S.H.I.E.L.D. supports (by distinct title). Cable:
      unlimited player side schemes (type only). Wonder Man: unlimited events
      with a printed energy resource.
  """

  @type allowance :: %{
          required(:types) => [atom()],
          required(:label) => String.t(),
          optional(:traits) => [String.t()],
          optional(:resource) => :energy | :physical | :mental | :wild,
          optional(:limit) => pos_integer(),
          optional(:limit_by) => :copies | :titles
        }

  @type t :: %__MODULE__{
          max_aspects: pos_integer(),
          equal_aspects: boolean(),
          single_copy: boolean(),
          off_aspect_allowance: allowance() | nil
        }

  defstruct max_aspects: 1,
            equal_aspects: false,
            single_copy: false,
            off_aspect_allowance: nil

  @doc "The deckbuilding exceptions for a hero `set`, or the standard template."
  @spec for_set(String.t() | nil) :: t()
  def for_set(set) do
    case set do
      # Double Agent: choose two aspects, equal number of cards from each.
      "spider_woman" ->
        %__MODULE__{max_aspects: 2, equal_aspects: true}

      # No single aspect — all four, with a single copy of each card.
      "warlock" ->
        %__MODULE__{max_aspects: 4, equal_aspects: true, single_copy: true}

      # Skilled Tactician: chosen aspect plus up to 6 attack/thwart events from
      # any other aspect.
      "gam" ->
        %__MODULE__{
          off_aspect_allowance: %{
            traits: ["Attack", "Thwart"],
            types: [:event],
            limit: 6,
            label: "attack/thwart events"
          }
        }

      # Scott Summers: may include X-Men allies from any aspect (no limit).
      "cyclops" ->
        %__MODULE__{
          off_aspect_allowance: %{
            traits: ["X-Men"],
            types: [:ally],
            label: "X-Men allies"
          }
        }

      # Maria Hill: up to 3 S.H.I.E.L.D. supports from other aspects (by title).
      "maria_hill" ->
        %__MODULE__{
          off_aspect_allowance: %{
            traits: ["S.H.I.E.L.D."],
            types: [:support],
            limit: 3,
            limit_by: :titles,
            label: "S.H.I.E.L.D. supports"
          }
        }

      # Nathan Summers: may include player side schemes from any aspect (no
      # trait restriction, no limit).
      "cable" ->
        %__MODULE__{
          off_aspect_allowance: %{
            types: [:player_side_scheme],
            label: "player side schemes"
          }
        }

      # Simon Williams: may include events with a printed energy resource from
      # any aspect.
      "wonder_man" ->
        %__MODULE__{
          off_aspect_allowance: %{
            types: [:event],
            resource: :energy,
            label: "events with an energy resource"
          }
        }

      _standard ->
        %__MODULE__{}
    end
  end

  @doc "The standard template (no exceptions)."
  @spec standard() :: t()
  def standard, do: %__MODULE__{}
end
