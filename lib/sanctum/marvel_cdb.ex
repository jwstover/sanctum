defmodule Sanctum.MarvelCdb do
  @moduledoc false

  alias Sanctum.Games.Card
  alias Sanctum.Decks
  alias Sanctum.Games

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
        |> Decks.create_with_cards(load: [:hero, :cards])

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

    {:ok, hero} = load_card(decklist["hero_code"])
    {:ok, _alter_ego} = load_card(alter_ego_code)

    card_codes = Map.keys(cards_map)

    cards =
      Enum.map(card_codes, fn card_code ->
        card = load_card!(card_code)
        {card.code, card}
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
      hero_code: hero.code,
      alter_ego_code: alter_ego_code,
      card_ids: card_ids
    }
  end

  def load_pack(pack_code) when is_binary(pack_code) do
    get_cards_by_pack(pack_code)
    |> case do
      {:ok, cards} ->
        cards
        |> Enum.map(&prepare_card_attrs/1)
        |> Ash.bulk_create!(Card, :create,
          upsert?: true,
          upsert_identity: :unique_marvelcdb_code,
          upsert_fields: [:replace_all]
        )
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
            prepare_card_attrs(resp)
            |> Sanctum.Games.create_card()

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

  # %{
  #   "scheme" => 1,
  #   "traits" => "Brute. Criminal.",
  #   "set_position" => 1,
  #   "thwart_star" => false,
  #   "pack_name" => "Core Set",
  #   "threat_fixed" => false,
  #   "card_set_code" => "rhino",
  #   "attack_star" => false,
  #   "stage" => 1,
  #   "permanent" => false,
  #   "health" => 14,
  #   "position" => 94,
  #   "cost_per_hero" => false,
  #   "health_per_hero" => true,
  #   "octgn_id" => "fce46ea8-8d92-4ddc-8ef0-9c923fcf6afd",
  #   "card_set_type_name_code" => "villain",
  #   "hidden" => false,
  #   "is_unique" => true,
  #   "type_name" => "Villain",
  #   "code" => "01094",
  #   "faction_code" => "encounter",
  #   "card_set_name" => "Rhino",
  #   "flavor" => "\"I'm Rhino, I knock things down. That's what I do. That's who I am.\"",
  #   "name" => "Rhino",
  #   "base_threat_fixed" => false,
  #   "attack" => 2,
  #   "real_traits" => "Brute. Criminal.",
  #   "boost_star" => false,
  #   "imagesrc" => "/bundles/cards/01094.png",
  #   "quantity" => 1,
  #   "defense_star" => false,
  #   "url" => "https://marvelcdb.com/card/01094",
  #   "spoiler" => 1,
  #   "faction_name" => "Encounter",
  #   "real_name" => "Rhino",
  #   "double_sided" => false,
  #   "pack_code" => "core",
  #   "escalation_threat_fixed" => false,
  #   "type_code" => "villain",
  #   "recover_star" => false,
  #   "health_star" => false,
  #   "scheme_star" => false,
  #   "escalation_threat_star" => false,
  #   "threat_star" => false
  # }

  defp prepare_card_attrs(%{} = mcdb_card) do
    %{
      # Core identity fields
      name: mcdb_card["name"],
      subname: mcdb_card["real_name"],
      code: mcdb_card["code"],
      text: mcdb_card["text"] || mcdb_card["real_text"],
      traits: parse_traits(mcdb_card["real_traits"] || mcdb_card["traits"]),

      # Card classification using new enums
      type: map_card_type(mcdb_card["type_code"]),
      aspect: map_aspect(mcdb_card["faction_code"]),

      # Combat stats
      attack: mcdb_card["attack"],
      thwart: mcdb_card["thwart"],
      defense: mcdb_card["defense"],
      health: mcdb_card["health"],

      # Cost and economics
      cost: mcdb_card["cost"],
      deck_limit: mcdb_card["quantity"] || 1,
      unique: mcdb_card["is_unique"] || false,
      permanent: mcdb_card["permanent"] || false,

      # Icons (using existing boost_star mapping as example)
      boost_star: mcdb_card["boost_star"] || false,

      # Hero-specific fields
      hand_size: mcdb_card["hand_size"],
      recover: mcdb_card["recover"],

      # Villain-specific fields
      health_per_hero: mcdb_card["health_per_hero"] || false,
      stage: mcdb_card["stage"],
      scheme: mcdb_card["scheme"],

      # Scheme-specific fields
      base_threat: mcdb_card["base_threat"],
      escalation_threat: mcdb_card["escalation_threat"],
      max_threat: mcdb_card["threat"],

      # Encounter-specific fields
      boost: mcdb_card["boost"],

      # Categorization fields
      set: mcdb_card["card_set_code"],
      pack: mcdb_card["pack_code"],
      image_url: build_image_url(mcdb_card["imagesrc"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
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
