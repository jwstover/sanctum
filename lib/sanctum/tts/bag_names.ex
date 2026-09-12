defmodule Sanctum.TTS.BagNames do
  @moduledoc """
  Translates Sanctum heroes, cards, and side decks into the **bag entry names**
  used by Hitch's Marvel Champions mod for Tabletop Simulator.

  The TTS importer tile clones objects out of the mod's own bags, so the server
  has to hand it strings that match those bags' `Nickname`/`Description` fields
  rather than Sanctum's internal ids. This module is that translation layer: a
  pure function of already-loaded structs. It performs no reads — the API
  layer loads `:primary_side` (cards) and the hero before calling in.

  ## Bag shapes

  | Piece | Bag entry name |
  |---|---|
  | Identity + obligation + nemesis set | `"<hero>"` |
  | Hero kit (signature cards) | `"<hero> Cards"` |
  | HP counter | `"<hero>'s HP Counter"` |
  | Side decks | literal names, see `side_deck_bag_name/1` |
  | Individual player cards | `(pool, name, subname)` inside a pool bag |

  ## Subname normalization

  The mod matches a card by `Nickname == name` **and** `Description == subname`.
  Sanctum's catalog stores three different "no subtitle" spellings — `nil`,
  `""`, and `subname == name` (most identity cards) — so `card_lookup/1`
  collapses all three to **`nil`**. That is the contract with the tile: a `nil`
  (JSON `null`) subname means "match cards whose Description is empty". Only
  cards with a genuinely distinct subtitle ("Hawkeye" / "Clint Barton") carry
  a string.

  ## Hero names

  `Hero.hero_name` matches the mod's bag names directly for all but two heroes.
  The alternate Spider-Man and Black Panther share a printed name with the
  originals and the mod disambiguates them with an alter-ego suffix, keyed on
  the hero's `base_code` (Sanctum stores the bare card number, e.g. `"27030"`;
  the side-lettered form `"27030a"` is accepted too).
  """

  alias Sanctum.Decks.SideDeck

  @typedoc "A card's lookup key inside one of the mod's pool bags."
  @type card_lookup :: %{pool: String.t(), name: String.t(), subname: String.t() | nil}

  @typedoc "The three per-hero bag entries the tile clones."
  @type hero_bag_names :: %{identity: String.t(), kit: String.t(), hp_counter: String.t()}

  # Cerebro's suffix rule for heroes whose printed name collides with another
  # hero's. Keyed on the bare base_code (no side letter).
  @hero_suffixes %{
    "27030" => " (Miles Morales)",
    "51001" => " (Shuri)"
  }

  # Sanctum aspect key -> the mod's pool bag for that aspect. `pool` is an
  # aspect key in Sanctum (Deadpool's 'Pool), not an ownership.
  @aspect_pools %{
    "aggression" => "AggressionCards",
    "justice" => "JusticeCards",
    "leadership" => "LeadershipCards",
    "protection" => "ProtectionCards",
    "pool" => "PoolCards"
  }

  @basic_pool "BasicCards"

  # Sanctum side-deck set slug (`SideDeck.key`) -> the mod's literal bag name.
  # The mod hero-prefixes these ("Doctor Strange Invocation Deck"); we map by
  # explicit table rather than by pattern so an unknown deck reports a miss
  # (`nil`) instead of inventing a name. Iceman's Frostbite cards ship in the
  # catalog under `iceman_frostbite` (no `_deck` suffix), so both slugs map.
  @side_deck_bags %{
    "storm_weather_deck" => "Storm Weather Deck",
    "doctor_strange_invocation_deck" => "Doctor Strange Invocation Deck",
    "iceman_frostbite_deck" => "Iceman Frostbite Deck",
    "iceman_frostbite" => "Iceman Frostbite Deck",
    "hercules_gift_deck" => "Hercules Gift Deck",
    "hercules_labor_deck" => "Hercules Labor Deck"
  }

  @doc """
  The mod's name for a hero: `hero_name`, plus the alter-ego suffix for the
  two same-name alternates.

      iex> hero_name(%{hero_name: "Spider-Man", base_code: "27030"})
      "Spider-Man (Miles Morales)"
  """
  @spec hero_name(%{hero_name: String.t(), base_code: String.t() | nil}) :: String.t()
  def hero_name(%{hero_name: name, base_code: base_code}) when is_binary(name) do
    name <> Map.get(@hero_suffixes, bare_base_code(base_code), "")
  end

  @doc """
  The three per-hero bag entries: the identity/obligation/nemesis set, the
  signature-card kit, and the HP counter tile.

      iex> hero_bag_names(%{hero_name: "Storm", base_code: "45001"})
      %{identity: "Storm", kit: "Storm Cards", hp_counter: "Storm's HP Counter"}
  """
  @spec hero_bag_names(%{hero_name: String.t(), base_code: String.t() | nil}) :: hero_bag_names()
  def hero_bag_names(hero) do
    name = hero_name(hero)

    %{
      identity: name,
      kit: name <> " Cards",
      hp_counter: name <> "'s HP Counter"
    }
  end

  @doc """
  The `(pool, name, subname)` lookup the tile uses to find one player card
  inside the mod's pool bags, or `nil` when the card is not looked up per card.

  Accepts a `Sanctum.Games.Card` with `:primary_side` loaded, or a
  `Sanctum.Games.CardSide` directly.

  * ownership `:basic` -> `"BasicCards"`
  * ownership `:player` -> the aspect's bag (`"JusticeCards"`, `"PoolCards"`, …)
  * ownership `:hero` -> `nil`; signature cards come from the hero kit deck
  * `:encounter` / `:campaign`, or a `:player` card with an unmapped (custom)
    aspect -> `nil`
  * a card with no primary side at all (nothing to name it by) -> `nil`

  `subname` is normalized per the module docs: `nil`, `""`, and `== name` all
  become `nil`.
  """
  @spec card_lookup(map()) :: card_lookup() | nil
  def card_lookup(%{primary_side: %Ash.NotLoaded{}}) do
    raise ArgumentError, "card_lookup/1 needs the card's :primary_side loaded"
  end

  def card_lookup(%{primary_side: nil}), do: nil
  def card_lookup(%{primary_side: %{name: _} = side}), do: card_lookup(side)

  def card_lookup(%{name: name, ownership: ownership} = side) when is_binary(name) do
    case pool(ownership, Map.get(side, :aspect)) do
      nil -> nil
      pool -> %{pool: pool, name: name, subname: normalize_subname(name, Map.get(side, :subname))}
    end
  end

  @doc """
  The mod's literal bag name for a built-in side deck, or `nil` when the mod
  has no such deck (e.g. Daredevil's Sense deck). Accepts a
  `Sanctum.Decks.SideDeck` or its `key` (the catalog set slug).
  """
  @spec side_deck_bag_name(SideDeck.t() | String.t()) :: String.t() | nil
  def side_deck_bag_name(%SideDeck{key: key}), do: side_deck_bag_name(key)
  def side_deck_bag_name(key) when is_binary(key), do: Map.get(@side_deck_bags, key)

  @doc """
  Collapses the catalog's three "no subtitle" spellings to `nil`. See the
  module docs for why this is the tile contract.
  """
  @spec normalize_subname(String.t(), String.t() | nil) :: String.t() | nil
  def normalize_subname(_name, nil), do: nil
  def normalize_subname(_name, ""), do: nil
  def normalize_subname(name, name), do: nil
  def normalize_subname(_name, subname) when is_binary(subname), do: subname

  defp pool(:basic, _aspect), do: @basic_pool
  defp pool(:player, aspect) when is_binary(aspect), do: Map.get(@aspect_pools, aspect)
  defp pool(_ownership, _aspect), do: nil

  # "27030a" -> "27030"; already-bare codes pass through.
  defp bare_base_code(code) when is_binary(code), do: String.replace(code, ~r/[a-z]$/, "")
  defp bare_base_code(_code), do: nil
end
