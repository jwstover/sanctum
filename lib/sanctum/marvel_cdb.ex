defmodule Sanctum.MarvelCdb do
  @moduledoc """
  Client for the MarvelCDB public API.

  Cards are processed as *groups*: all payload entries sharing a base code
  (e.g. `01097`, `01097a`, `01097b`) resolve to one `Card` with one `CardSide`
  per face. Grouping is required because MarvelCDB's representation varies by
  card type:

    * heroes are suffixed sibling entries only (`01001a`/`01001b`, up to `c`
      for 3-form heroes like Angel — nothing links `c`, so link-chains can't
      be trusted)
    * main schemes add a `double_sided` parent entry that alone carries the
      front image (`imagesrc`) and back image (`backimagesrc`); the `a` entry
      has no image of its own
    * a few double-sided cards (Intangible, `26002`) have *only* the parent —
      both faces must be synthesized from it

  Unknown card codes answer with HTTP 500 (not 404), so single-card fetches
  never retry.
  """

  require Logger

  alias Sanctum.Decks
  alias Sanctum.Games
  alias Sanctum.Heroes

  @base_url "https://marvelcdb.com/api/public"

  @doc """
  Imports a single deck from a MarvelCDB URL or bare id.

  Accepts published decklist URLs (`/decklist/view/{id}`), private-but-public
  deck URLs (`/deck/view/{id}`), or a bare decklist id. The two MarvelCDB id
  spaces are distinct objects, so the resolved `mcdb_type` is stored alongside
  the id.
  """
  def load_deck("https://marvelcdb.com/decklist/view/" <> rest) when is_binary(rest) do
    [deck_id | _] = String.split(rest, "/")
    fetch_and_import(:decklist, deck_id)
  end

  def load_deck("https://marvelcdb.com/deck/view/" <> rest) when is_binary(rest) do
    [deck_id | _] = String.split(rest, "/")
    fetch_and_import(:deck, deck_id)
  end

  def load_deck(mcdb_deck_id) when is_binary(mcdb_deck_id) do
    fetch_and_import(:decklist, mcdb_deck_id)
  end

  defp fetch_and_import(mcdb_type, mcdb_deck_id) do
    endpoint = if mcdb_type == :deck, do: "deck", else: "decklist"

    "#{@base_url}/#{endpoint}/#{mcdb_deck_id}"
    |> Req.get([max_retries: 1] ++ req_options())
    |> handle_response()
    |> case do
      {:ok, decklist} -> import_decklist(decklist, mcdb_type: mcdb_type)
      err -> err
    end
  end

  @doc """
  Upserts one deck (and replaces its card list) from a raw MarvelCDB decklist
  payload. Shared by single-URL import and the scheduled by-date sync.

  Options:

    * `:mcdb_type` — `:decklist` (default) or `:deck`, stored to disambiguate
      the id space.
  """
  def import_decklist(decklist, opts \\ []) do
    decklist
    |> prepare_deck_attrs(Keyword.get(opts, :mcdb_type, :decklist))
    |> Decks.create_with_cards(load: [:cards, hero: [:hero_side, :alter_ego_side]])
  end

  defp prepare_deck_attrs(%{"slots" => cards_map} = decklist, mcdb_type) do
    alter_ego_code =
      decklist["hero_code"]
      |> String.trim()
      |> String.trim_trailing("a")
      |> Kernel.<>("b")

    {:ok, hero_card} = load_card(decklist["hero_code"])
    {:ok, alter_ego_card} = load_card(alter_ego_code)

    # Create or find the Hero record
    {:ok, hero} = create_or_find_hero(hero_card, alter_ego_card)

    {:ok, mcdb_user} = create_or_find_mcdb_user(decklist["user_id"])

    meta = parse_meta(decklist["meta"])

    slots = build_slots(cards_map, decklist["ignoreDeckLimitSlots"] || %{})

    %{
      mcdb_id: decklist["id"] |> to_string(),
      mcdb_type: mcdb_type,
      source: :marvelcdb,
      title: decklist["name"],
      hero_id: hero.id,
      mcdb_user_id: mcdb_user && mcdb_user.id,
      aspects: parse_aspects(meta),
      meta: meta,
      tags: presence(decklist["tags"]),
      description_md: presence(decklist["description_md"]),
      version: presence(decklist["version"]),
      slots: slots
    }
  end

  # MarvelCDB keys `slots` by side code (e.g. 01043a/b/c/d), but several codes
  # can resolve to one Sanctum `Card` (grouped by base code) — a card that ships
  # as multiple physical copies, each with its own code. Aggregate by resolved
  # `card_id`, summing quantities and OR-ing the deck-limit-ignore flag.
  defp build_slots(cards_map, ignore_limits) do
    cards_map
    |> Enum.reduce(%{}, fn {code, count}, acc ->
      card_id = load_card!(code).id
      ignore? = Map.has_key?(ignore_limits, code)

      Map.update(acc, card_id, %{quantity: count, ignore_deck_limit: ignore?}, fn slot ->
        %{
          quantity: slot.quantity + count,
          ignore_deck_limit: slot.ignore_deck_limit or ignore?
        }
      end)
    end)
    |> Enum.map(fn {card_id, slot} -> Map.put(slot, :card_id, card_id) end)
  end

  # MarvelCDB stores `meta` as a JSON-encoded string (or nil/empty).
  defp parse_meta(meta) when is_binary(meta) and meta != "" do
    case Jason.decode(meta) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_meta(_meta), do: %{}

  # Aspects live in meta as flat `aspect`, `aspect2`, ... keys; collect them in
  # order and map to atoms. Unknown values (or a basic deck with none) drop out,
  # leaving an empty list.
  defp parse_aspects(meta) do
    meta
    |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "aspect") end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {_k, v} -> map_deck_aspect(v) end)
    |> Enum.reject(&is_nil/1)
  end

  defp map_deck_aspect(value) do
    case value do
      "aggression" -> :aggression
      "justice" -> :justice
      "leadership" -> :leadership
      "protection" -> :protection
      "pool" -> :pool
      _ -> nil
    end
  end

  defp create_or_find_mcdb_user(nil), do: {:ok, nil}

  defp create_or_find_mcdb_user(mcdb_user_id) when is_integer(mcdb_user_id) do
    Decks.find_or_create_mcdb_user(%{mcdb_user_id: mcdb_user_id})
  end

  defp create_or_find_hero(hero_card, _alter_ego_card) do
    # Load the card with all its sides to get both hero and alter ego names
    card_loaded = Games.get_card!(hero_card.id, load: [:card_sides])

    hero_side = Enum.find(card_loaded.card_sides, &(&1.type == :hero))
    alter_ego_side = Enum.find(card_loaded.card_sides, &(&1.type == :alter_ego))

    hero_attrs = %{
      hero_name: hero_side.name,
      alter_ego_name: alter_ego_side.name,
      set: hero_card.set,
      base_code: hero_card.base_code,
      card_id: hero_card.id
    }

    Heroes.find_or_create_hero(hero_attrs)
  end

  defp create_or_find_villain(card, side) when side.type == :villain do
    villain_attrs = %{
      villain_name: side.name,
      set: card.set
    }

    Sanctum.Villains.find_or_create_villain(villain_attrs)
  end

  defp create_or_find_villain(_card, _side), do: {:ok, nil}

  def load_pack(pack_code, opts \\ []) when is_binary(pack_code) do
    with {:ok, cards} <- get_cards_by_pack(pack_code) do
      case sync_entries(cards, opts) do
        {_synced, []} -> :ok
        {_synced, failures} -> {:error, failures}
      end
    end
  end

  @doc """
  Upserts cards and their sides from a list of raw MarvelCDB payload entries.

  Entries are grouped by base code and each group is processed as one card.
  Returns `{synced_count, failures}` where failures are `{base_code, error}`
  tuples; a failing group never aborts the rest.

  Options:

    * `:image_url_fun` — maps a resolved `imagesrc` path (or nil) to the URL
      stored on the side. Defaults to an absolute marvelcdb.com URL;
      `Sanctum.CardSync` passes `Sanctum.CardImages.public_url/1` to point at
      the mirrored bucket instead.
    * `:on_progress` — called after each card group with
      `%{index, total, base_code, name, ok?}`.
  """
  def sync_entries(entries, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress)

    groups =
      entries
      |> Enum.uniq_by(& &1["code"])
      |> Enum.group_by(&extract_base_code(&1["code"]))
      |> Enum.sort_by(fn {base_code, _group} -> base_code end)

    total = length(groups)

    groups
    |> Enum.with_index(1)
    |> Enum.reduce({0, []}, fn {{base_code, group}, index}, {synced, failures} ->
      result = create_card_from_entries(group, opts)

      if on_progress do
        on_progress.(%{
          index: index,
          total: total,
          base_code: base_code,
          name: group_name(group),
          ok?: match?({:ok, _}, result)
        })
      end

      case result do
        {:ok, _card} -> {synced + 1, failures}
        {:error, error} -> {synced, [{base_code, error} | failures]}
      end
    end)
    |> then(fn {synced, failures} -> {synced, Enum.reverse(failures)} end)
  end

  defp group_name(group), do: Enum.find_value(group, &presence(&1["name"]))

  def load_card(card_id) when is_integer(card_id) do
    card_id
    |> Integer.to_string()
    |> String.pad_leading(5, "0")
    |> load_card()
  end

  def load_card(card_id) when is_binary(card_id) do
    Games.get_card_side_by_code(card_id, load: [:card])
    |> case do
      {:ok, %Games.CardSide{card: %Games.Card{} = card}} ->
        Logger.info("Not loading existing card #{card_id}")
        {:ok, card}

      _ ->
        fetch_and_create_card(card_id)
    end
  end

  # Fetches the card, then its pack listing, and processes every entry sharing
  # the card's base code — the only reliable way to find all sides (parents,
  # orphaned `c`/`d` sides) without probing guessed codes.
  defp fetch_and_create_card(card_id) do
    with {:ok, mcdb_card} <- fetch_card(card_id),
         {:ok, pack_entries} <- get_cards_by_pack(mcdb_card["pack_code"]) do
      base_code = extract_base_code(mcdb_card["code"])

      pack_entries
      |> Enum.filter(&(extract_base_code(&1["code"]) == base_code))
      |> case do
        [] -> create_card_from_entries([mcdb_card])
        group -> create_card_from_entries(group)
      end
    end
  end

  def load_card!(card_id) when is_binary(card_id) do
    case load_card(card_id) do
      {:ok, card} ->
        card

      {:error, reason} ->
        raise "failed to load card #{card_id}: #{inspect(reason)}"
    end
  end

  @spec get_cards_by_pack(String.t()) :: {:ok, list(map())} | {:error, term()}
  def get_cards_by_pack(pack_code) when is_binary(pack_code) do
    "#{@base_url}/cards/#{pack_code}"
    |> Req.get([max_retries: 1] ++ req_options())
    |> handle_response()
  end

  @doc """
  Fetches every published decklist created on `date` (a `Date`), as full
  decklist payloads. This is the source for incremental deck sync.
  """
  @spec get_decklists_by_date(Date.t()) :: {:ok, list(map())} | {:error, term()}
  def get_decklists_by_date(%Date{} = date) do
    "#{@base_url}/decklists/by_date/#{Date.to_iso8601(date)}"
    |> Req.get([max_retries: 1] ++ req_options())
    |> handle_response()
  end

  @doc "Fetches every card (player + encounter) as a single payload."
  @spec get_all_cards() :: {:ok, list(map())} | {:error, term()}
  def get_all_cards do
    "#{@base_url}/cards/?encounter=1"
    |> Req.get([max_retries: 1] ++ req_options())
    |> handle_response()
  end

  # MarvelCDB answers unknown card codes with HTTP 500, which Req's default
  # retry treats as transient — never retry single-card fetches.
  defp fetch_card(card_id) do
    "#{@base_url}/card/#{card_id}"
    |> Req.get([retry: false] ++ req_options())
    |> handle_response()
  end

  @doc """
  Creates/updates one card and all its sides from the payload entries sharing
  a base code. See `sync_entries/2` for options.
  """
  def create_card_from_entries(entries, opts \\ []) do
    image_url_fun = Keyword.get(opts, :image_url_fun, &build_image_url/1)

    parent = Enum.find(entries, &(!suffixed?(&1["code"])))
    side_entries = side_entries(entries, parent)

    card_entry = parent || hd(side_entries)
    primary_code = side_entries |> hd() |> Map.fetch!("code")
    card_attrs = prepare_card_attrs(card_entry, primary_code, length(side_entries) > 1)

    # Catalog writes are system-level (sync, seeds, player deck import) and
    # bypass the admin-only Card/CardSide policies.
    with {:ok, card} <- Games.create_card(card_attrs, authorize?: false),
         :ok <- upsert_sides(card, side_entries, parent, image_url_fun) do
      maybe_upsert_hero(card, entries)
      {:ok, card}
    end
  end

  # Hero identity groups carry the hero's color palette in the identity card's
  # `meta.colors`. Upsert a Hero (keyed by set) with that palette so the Hero
  # table is complete and colors are available regardless of deck imports.
  defp maybe_upsert_hero(card, entries) do
    with hero_entry when is_map(hero_entry) <-
           Enum.find(entries, &(&1["type_code"] == "hero")) do
      alter_ego = Enum.find(entries, &(&1["type_code"] == "alter_ego"))
      colors = get_in(hero_entry, ["meta", "colors"])
      {primary, secondary} = pick_gradient(colors)

      Heroes.find_or_create_hero(
        %{
          hero_name: hero_entry["name"],
          alter_ego_name: alter_ego && alter_ego["name"],
          set: hero_entry["card_set_code"],
          base_code: extract_base_code(hero_entry["code"]),
          card_id: card.id,
          colors: colors,
          primary_color: primary,
          secondary_color: secondary
        },
        authorize?: false
      )
    end

    :ok
  end

  # Minimum RGB distance for two palette colors to read as a distinct gradient.
  @min_gradient_distance 64

  # Chooses the two gradient colors from a MarvelCDB palette. The base is always
  # the first color; the accent is the second color when it's visibly different,
  # otherwise the third — some heroes (e.g. Black Widow) lead with two near-black
  # colors, so the second would give a near-invisible gradient.
  def pick_gradient(colors) when is_list(colors) do
    case colors do
      [] ->
        {nil, nil}

      [only] ->
        {only, only}

      [first | _] ->
        second = Enum.at(colors, 1)
        third = Enum.at(colors, 2)

        accent =
          cond do
            distinct?(first, second) -> second
            is_binary(third) and not near_white?(third) -> third
            true -> second
          end

        {first, accent}
    end
  end

  def pick_gradient(_), do: {nil, nil}

  defp distinct?(a, b) do
    with {r1, g1, b1} <- hex_to_rgb(a),
         {r2, g2, b2} <- hex_to_rgb(b) do
      dist = :math.sqrt(:math.pow(r1 - r2, 2) + :math.pow(g1 - g2, 2) + :math.pow(b1 - b2, 2))
      dist >= @min_gradient_distance
    else
      _ -> true
    end
  end

  defp near_white?(hex) do
    case hex_to_rgb(hex) do
      {r, g, b} -> r > 240 and g > 240 and b > 240
      _ -> false
    end
  end

  defp hex_to_rgb("#" <> hex) when byte_size(hex) == 6 do
    case Integer.parse(hex, 16) do
      {int, ""} -> {div(int, 65_536), div(rem(int, 65_536), 256), rem(int, 256)}
      _ -> :error
    end
  end

  defp hex_to_rgb(_), do: :error

  defp side_entries(entries, parent) do
    sides = entries |> Enum.filter(&suffixed?(&1["code"])) |> Enum.sort_by(& &1["code"])

    if parent && parent["double_sided"] do
      fill_missing_sides(sides, parent)
    else
      if sides == [], do: [parent], else: sides
    end
  end

  # Pack payloads omit hidden side entries (main-scheme B sides only appear in
  # the all-cards payload), and a few cards have no side entries at all
  # (Intangible) — fill whatever is missing from the parent, which alone
  # carries both faces.
  defp fill_missing_sides(sides, parent) do
    identifiers = MapSet.new(sides, &extract_side_identifier(&1["code"]))
    [front, back] = synthesize_side_entries(parent)

    sides
    |> then(&if MapSet.member?(identifiers, "a"), do: &1, else: [front | &1])
    |> then(&if MapSet.member?(identifiers, "b"), do: &1, else: &1 ++ [back])
    |> Enum.sort_by(& &1["code"])
  end

  defp upsert_sides(card, side_entries, parent, image_url_fun) do
    Enum.reduce_while(side_entries, :ok, fn entry, :ok ->
      image_url = entry |> resolve_imagesrc(parent) |> image_url_fun.()

      case upsert_side(card, prepare_card_side_attrs(entry, image_url)) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp upsert_side(card, side_attrs) do
    attrs = Map.put(side_attrs, :card_id, card.id)

    find_existing_side(card, attrs)
    |> case do
      {:ok, existing} -> Games.update_card_side(existing, attrs, authorize?: false)
      {:error, _not_found} -> Games.create_card_side(attrs, authorize?: false)
    end
    |> case do
      {:ok, side} ->
        create_or_find_villain(card, side)
        :ok

      err ->
        err
    end
  end

  # The card+identifier fallback catches rows written by older sync logic
  # under a differently-suffixed code (e.g. "01144" where the payload now says
  # "01144a"); updating them corrects the code in place.
  defp find_existing_side(card, attrs) do
    case Games.get_card_side_by_code(attrs.code) do
      {:ok, existing} -> {:ok, existing}
      {:error, _} -> Games.get_card_side_by_card_and_side(card.id, attrs.side_identifier)
    end
  end

  # The side's image with fallback to the double-sided parent entry, which
  # alone carries the front (`imagesrc`) and back (`backimagesrc`) scans for
  # main schemes and friends.
  defp resolve_imagesrc(entry, parent) do
    cond do
      src = presence(entry["imagesrc"]) -> src
      is_nil(parent) -> nil
      extract_side_identifier(entry["code"]) == "a" -> presence(parent["imagesrc"])
      extract_side_identifier(entry["code"]) == "b" -> presence(parent["backimagesrc"])
      true -> nil
    end
  end

  # Double-sided cards without their own side entries (Intangible, 26002)
  # carry both faces on the parent: front as the entry itself, back via
  # back_name/back_text/backimagesrc.
  defp synthesize_side_entries(parent) do
    code = parent["code"]

    front = Map.put(parent, "code", code <> "a")

    back =
      Map.merge(parent, %{
        "code" => code <> "b",
        "name" => parent["back_name"] || parent["name"],
        "real_name" => nil,
        "text" => parent["back_text"],
        "real_text" => nil,
        "flavor" => parent["back_flavor"],
        "imagesrc" => presence(parent["backimagesrc"])
      })

    [front, back]
  end

  defp suffixed?(code), do: String.match?(code, ~r/[a-z]$/)

  defp presence(value) when value in [nil, ""], do: nil
  defp presence(value), do: value

  def extract_base_code(code) do
    # Remove trailing letter (e.g., "01001a" -> "01001")
    String.replace(code, ~r/[a-z]$/, "")
  end

  def extract_side_identifier(code) do
    # Extract trailing letter (e.g., "01001a" -> "a"), default to "a"
    case Regex.run(~r/([a-z])$/, code) do
      [_, letter] -> letter
      nil -> "a"
    end
  end

  defp prepare_card_attrs(%{} = mcdb_card, primary_code, is_multi_sided) do
    %{
      # Multi-sided card support
      is_multi_sided: is_multi_sided,
      base_code: extract_base_code(mcdb_card["code"]),

      # Primary side code (for compatibility)
      code: primary_code,

      # Card-level properties
      deck_limit: mcdb_card["quantity"] || 1,
      unique: mcdb_card["is_unique"] || false,
      permanent: mcdb_card["permanent"] || false,

      # Categorization fields
      set: mcdb_card["card_set_code"],
      pack: mcdb_card["pack_code"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp prepare_card_side_attrs(%{} = mcdb_card, image_url) do
    side_identifier = extract_side_identifier(mcdb_card["code"])

    %{
      # Side identification
      side_identifier: side_identifier,
      is_primary_side: side_identifier == "a",
      code: mcdb_card["code"],

      # Core card content. MarvelCDB carries both localized (`name`/`text`/
      # `traits`) and unlocalized-English `real_*` variants; for an English-only
      # app the non-`real_` fields are canonical.
      name: mcdb_card["name"],
      subname: mcdb_card["subname"],
      text: mcdb_card["text"],
      flavor: mcdb_card["flavor"],
      traits: parse_traits(mcdb_card["traits"]),

      # Card classification. faction_code is split into ownership (which pool)
      # and aspect (only the four player aspects).
      type: map_card_type(mcdb_card["type_code"]),
      ownership: map_ownership(mcdb_card["faction_code"]),
      aspect: map_aspect(mcdb_card["faction_code"]),

      # Combat stats (structured value/star/scaling)
      attack: stat(mcdb_card["attack"], mcdb_card["attack_star"], :flat),
      thwart: stat(mcdb_card["thwart"], mcdb_card["thwart_star"], :flat),
      defense: stat(mcdb_card["defense"], mcdb_card["defense_star"], :flat),
      health: stat(mcdb_card["health"], mcdb_card["health_star"], health_scaling(mcdb_card)),
      cost: mcdb_card["cost"],

      # Icons
      acceleration_icon: mcdb_card["acceleration_icon"] || false,
      amplify_icon: mcdb_card["amplify_icon"] || false,
      crisis_icon: mcdb_card["crisis_icon"] || false,
      hazard_icon: mcdb_card["hazard_icon"] || false,

      # Resource fields. MarvelCDB names these `resource_energy` (etc.); the
      # `resource_*_count` API variants are always null.
      resource_energy_count: mcdb_card["resource_energy"],
      resource_physical_count: mcdb_card["resource_physical"],
      resource_mental_count: mcdb_card["resource_mental"],
      resource_wild_count: mcdb_card["resource_wild"],

      # Hero fields
      hand_size: mcdb_card["hand_size"],
      recover: stat(mcdb_card["recover"], mcdb_card["recover_star"], :flat),

      # Villain fields (health scaling lives in health.scaling)
      stage: stage_to_integer(mcdb_card["stage"]),
      scheme: mcdb_card["scheme"],

      # Scheme fields (structured value/star/scaling)
      base_threat:
        stat(
          mcdb_card["base_threat"],
          false,
          threat_scaling(mcdb_card, "base_threat_per_group", "base_threat_fixed")
        ),
      escalation_threat:
        stat(
          mcdb_card["escalation_threat"],
          mcdb_card["escalation_threat_star"],
          threat_scaling(mcdb_card, "escalation_threat_per_group", "escalation_threat_fixed")
        ),
      max_threat:
        stat(
          mcdb_card["threat"],
          mcdb_card["threat_star"],
          threat_scaling(mcdb_card, "threat_per_group", "threat_fixed")
        ),

      # Encounter fields
      boost: mcdb_card["boost"],
      boost_star: mcdb_card["boost_star"] || false,

      # Image
      image_url: image_url
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Builds a structured stat map. A nil value means the stat is absent, so we
  # return nil and let the trailing Enum.reject drop the attribute entirely.
  defp stat(nil, _star, _scaling), do: nil
  defp stat(value, star, scaling), do: %{value: value, star: star || false, scaling: scaling}

  # Health scaling from MarvelCDB's booleans.
  defp health_scaling(entry) do
    cond do
      entry["health_per_hero"] -> :per_player
      entry["health_per_group"] -> :per_group
      true -> :flat
    end
  end

  # Threat scaling: X_per_group → :per_group, X_fixed → :flat, else :per_player.
  defp threat_scaling(entry, group_key, fixed_key) do
    cond do
      entry[group_key] -> :per_group
      entry[fixed_key] -> :flat
      true -> :per_player
    end
  end

  defp stage_to_integer(nil), do: nil

  defp stage_to_integer(stage) do
    case stage do
      "I" -> 1
      "II" -> 2
      "III" -> 3
      "1" -> 1
      "2" -> 2
      "3" -> 3
      "1A" -> 1
      "1B" -> 1
      "1C" -> 1
      "2A" -> 2
      "2B" -> 2
      "2C" -> 2
      "3A" -> 3
      "3B" -> 3
      "3C" -> 3
      _ -> nil
    end
  end

  defp map_card_type(type_code) do
    case type_code do
      "hero" -> :hero
      "alter_ego" -> :alter_ego
      "villain" -> :villain
      "main_scheme" -> :main_scheme
      "side_scheme" -> :side_scheme
      "ally" -> :ally
      "event" -> :event
      "resource" -> :resource
      "upgrade" -> :upgrade
      "support" -> :support
      "minion" -> :minion
      "treachery" -> :treachery
      "attachment" -> :attachment
      "environment" -> :environment
      "obligation" -> :obligation
      # Default fallback
      _ -> :resource
    end
  end

  # MarvelCDB's faction_code overloads ownership with aspect. Ownership is the
  # pool the card comes from; aspect is only the four player aspects.
  defp map_ownership(faction_code) do
    case faction_code do
      "aggression" -> :player
      "justice" -> :player
      "leadership" -> :player
      "protection" -> :player
      "basic" -> :basic
      "pool" -> :pool
      "hero" -> :hero
      "encounter" -> :encounter
      "campaign" -> :campaign
      _ -> nil
    end
  end

  defp map_aspect(faction_code) do
    case faction_code do
      "aggression" -> :aggression
      "justice" -> :justice
      "leadership" -> :leadership
      "protection" -> :protection
      _ -> nil
    end
  end

  defp build_image_url(nil), do: nil

  defp build_image_url(imagesrc) when is_binary(imagesrc) do
    case String.starts_with?(imagesrc, "http") do
      true -> imagesrc
      false -> "https://marvelcdb.com#{imagesrc}"
    end
  end

  defp parse_traits(nil), do: []
  defp parse_traits(""), do: []

  defp parse_traits(traits_string) when is_binary(traits_string) do
    traits_string
    |> String.split(". ")
    |> Enum.map(&trim_trait/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp trim_trait(string) when is_binary(string) do
    trait =
      string
      |> String.trim()

    trait
    |> String.split(".")
    |> case do
      [trait] -> trait
      [trait, ""] -> trait
      _ -> trait
    end
  end

  defp handle_response(response) do
    case response do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: status}} -> {:error, "Unexpected status code: #{status}"}
      {:error, exception} -> {:error, exception}
    end
  end

  defp req_options, do: Application.get_env(:sanctum, :marvel_cdb_req_options, [])
end
