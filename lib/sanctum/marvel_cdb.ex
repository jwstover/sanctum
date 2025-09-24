defmodule Sanctum.MarvelCdb do
  @moduledoc false

  alias Sanctum.Decks
  alias Sanctum.Games
  alias Sanctum.Heroes

  @base_url "https://marvelcdb.com/api/public"

  def load_deck("https://marvelcdb.com/decklist/view/" <> rest) when is_binary(rest) do
    [deck_id | _] = String.split(rest, "/")
    load_deck(deck_id)
  end

  def load_deck(mcdb_deck_id) when is_binary(mcdb_deck_id) do
    "#{@base_url}/decklist/#{mcdb_deck_id}"
    |> Req.get()
    |> handle_response()
    |> case do
      {:ok, decklist} ->
        decklist
        |> prepare_deck_attrs()
        |> Decks.create_with_cards(load: [:cards, hero: [:hero_card, :alter_ego_card]])

      err ->
        err
    end
  end

  defp prepare_deck_attrs(%{"slots" => cards_map} = decklist) do
    alter_ego_code =
      decklist["hero_code"]
      |> String.trim()
      |> String.trim_trailing("a")
      |> Kernel.<>("b")

    {:ok, hero_card} = load_card(decklist["hero_code"])
    {:ok, alter_ego_card} = load_card(alter_ego_code)

    # Create or find the Hero record
    {:ok, hero} = create_or_find_hero(hero_card, alter_ego_card)

    card_codes = Map.keys(cards_map)

    cards =
      Enum.map(card_codes, fn card_code ->
        card = load_card!(card_code)
        {card_code, card}
      end)
      |> Map.new()

    card_ids =
      Enum.reduce(cards_map, [], fn {code, count}, acc ->
        card = Map.get(cards, code)
        acc ++ Enum.map(1..count, fn _ -> card.id end)
      end)

    %{
      mcdb_id: decklist["id"] |> Integer.to_string(),
      title: decklist["name"],
      hero_id: hero.id,
      card_ids: card_ids
    }
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
      base_code: hero_card.base_code
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

  def load_pack(pack_code) when is_binary(pack_code) do
    get_cards_by_pack(pack_code)
    |> case do
      {:ok, cards} ->
        cards
        |> Enum.each(&create_card_with_sides/1)
    end
  end

  def load_card(card_id) when is_integer(card_id) do
    card_id
    |> Integer.to_string()
    |> String.pad_leading(5, "0")
    |> load_card()
  end

  def load_card(card_id) when is_binary(card_id) do
    Games.get_card_by_code(card_id)
    |> case do
      %Games.Card{} = card ->
        {:ok, card}

      _ ->
        "#{@base_url}/card/#{card_id}"
        |> Req.get()
        |> handle_response()
        |> case do
          {:ok, resp} ->
            create_card_with_sides(resp)

          err ->
            err
        end
    end
  end

  def load_card!(card_id) when is_binary(card_id) do
    case load_card(card_id) do
      {:ok, card} ->
        card

      err ->
        raise err
    end
  end

  @spec get_cards_by_pack(String.t()) :: {:ok, list(map())}
  def get_cards_by_pack(pack_code) when is_binary(pack_code) do
    "#{@base_url}/cards/#{pack_code}"
    |> Req.get()
    |> handle_response()
    |> case do
      {:ok, cards} ->
        {:ok, cards}

      err ->
        err
    end
  end

  defp create_card_with_sides(mcdb_card) do
    code = mcdb_card["code"]
    base_code = extract_base_code(code)
    side_identifier = extract_side_identifier(code)

    # Determine if card is multi-sided based on multiple indicators
    is_multi_sided = detect_multi_sided_card(mcdb_card, code, side_identifier)

    # Don't create a side for base codes without side identifiers when double_sided is true
    # This represents the card metadata, not a specific side
    should_create_side = should_create_card_side?(mcdb_card, code, side_identifier)

    card_attrs = prepare_card_attrs(mcdb_card, is_multi_sided)

    case Sanctum.Games.create_card(card_attrs) do
      {:ok, card} ->
        result =
          if should_create_side do
            # Check if this side already exists
            case Sanctum.Games.get_card_side_by_code(code) do
              {:ok, existing_side} ->
                # Side already exists, but create villain if needed
                create_or_find_villain(card, existing_side)
                :ok

              {:error, _} ->
                # Create the side
                side_attrs = prepare_card_side_attrs(mcdb_card)

                case Sanctum.Games.create_card_side(Map.put(side_attrs, :card_id, card.id)) do
                  {:ok, side} ->
                    # Create villain resource if this is a villain side
                    create_or_find_villain(card, side)
                    :ok

                  err ->
                    err
                end
            end
          else
            :ok
          end

        case result do
          :ok ->
            if is_multi_sided do
              load_additional_sides(card, base_code)
            end

            {:ok, card}

          err ->
            err
        end

      err ->
        err
    end
  end

  defp load_additional_sides(card, base_code) do
    # For multi-sided cards, try to load sides b, c, etc.
    ["b", "c", "d"]
    |> Enum.each(fn suffix ->
      side_code = base_code <> suffix

      case fetch_card_side(side_code) do
        {:ok, side_data} ->
          side_attrs =
            prepare_card_side_attrs(side_data)
            |> Map.put(:card_id, card.id)

          case Sanctum.Games.create_card_side(side_attrs) do
            {:ok, side} ->
              # Create villain resource if this is a villain side
              create_or_find_villain(card, side)

            _ ->
              :ok
          end

        # Side doesn't exist, continue
        _ ->
          :ok
      end
    end)
  end

  defp fetch_card_side(side_code) do
    "#{@base_url}/card/#{side_code}"
    |> Req.get()
    |> handle_response()
  end

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

  def detect_multi_sided_card(mcdb_card, code, _side_identifier) do
    explicit_double_sided = mcdb_card["double_sided"] || false
    has_side_suffix = String.match?(code, ~r/[a-z]$/)

    # A card is multi-sided if:
    # 1. MarvelCDB explicitly says it's double_sided, OR
    # 2. The code has a side suffix (a, b, c), which implies multiple sides exist
    explicit_double_sided || has_side_suffix
  end

  def should_create_card_side?(mcdb_card, code, _side_identifier) do
    has_side_suffix = String.match?(code, ~r/[a-z]$/)
    explicit_double_sided = mcdb_card["double_sided"] || false

    # Create a side if:
    # 1. Code has a side suffix (represents a specific side), OR
    # 2. Code has no suffix AND double_sided is false (single-sided card, treat as side 'a')
    has_side_suffix || (!has_side_suffix && !explicit_double_sided)
  end

  defp prepare_card_attrs(%{} = mcdb_card, is_multi_sided) do
    %{
      # Multi-sided card support
      is_multi_sided: is_multi_sided,
      base_code: extract_base_code(mcdb_card["code"]),

      # Primary side code (for compatibility)
      code: mcdb_card["code"],

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

  defp prepare_card_side_attrs(%{} = mcdb_card) do
    side_identifier = extract_side_identifier(mcdb_card["code"])

    %{
      # Side identification
      side_identifier: side_identifier,
      is_primary_side: side_identifier == "a",
      code: mcdb_card["code"],

      # Core card content
      name: mcdb_card["name"],
      subname: mcdb_card["real_name"],
      text: mcdb_card["text"] || mcdb_card["real_text"],
      traits: parse_traits(mcdb_card["real_traits"] || mcdb_card["traits"]),

      # Card classification
      type: map_card_type(mcdb_card["type_code"]),
      aspect: map_aspect(mcdb_card["faction_code"]),

      # Combat stats
      attack: mcdb_card["attack"],
      thwart: mcdb_card["thwart"],
      defense: mcdb_card["defense"],
      health: mcdb_card["health"],
      cost: mcdb_card["cost"],

      # Icons
      acceleration_icon: mcdb_card["acceleration_icon"] || false,
      amplify_icon: mcdb_card["amplify_icon"] || false,
      crisis_icon: mcdb_card["crisis_icon"] || false,
      hazard_icon: mcdb_card["hazard_icon"] || false,

      # Resource fields
      resource_energy_count: mcdb_card["resource_energy_count"],
      resource_physical_count: mcdb_card["resource_physical_count"],
      resource_mental_count: mcdb_card["resource_mental_count"],
      resource_wild_count: mcdb_card["resource_wild_count"],

      # Hero fields
      hand_size: mcdb_card["hand_size"],
      recover: mcdb_card["recover"],

      # Villain fields
      health_per_hero: mcdb_card["health_per_hero"] || false,
      stage: stage_to_integer(mcdb_card["stage"]),
      scheme: mcdb_card["scheme"],

      # Scheme fields
      base_threat: mcdb_card["base_threat"],
      escalation_threat: mcdb_card["escalation_threat"],
      max_threat: mcdb_card["threat"],

      # Encounter fields
      boost: mcdb_card["boost"],
      boost_star: mcdb_card["boost_star"] || false,

      # Image
      image_url: build_image_url(mcdb_card["imagesrc"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp stage_to_integer(nil), do: nil

  defp stage_to_integer(stage) do
    case stage do
      "I" -> 1
      "II" -> 2
      "III" -> 3
      "1A" -> 1
      "1B" -> 1
      "1C" -> 1
      "2A" -> 2
      "2B" -> 2
      "2C" -> 2
      "3A" -> 3
      "3B" -> 3
      "3C" -> 3
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

  defp map_aspect(faction_code) do
    case faction_code do
      "aggression" -> :aggression
      "justice" -> :justice
      "leadership" -> :leadership
      "protection" -> :protection
      "basic" -> :basic
      "encounter" -> :encounter
      _ -> nil
    end
  end

  defp build_image_url(nil), do: nil
  defp build_image_url(""), do: nil

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
    end
  end
end
