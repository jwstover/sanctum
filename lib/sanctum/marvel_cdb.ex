defmodule Sanctum.MarvelCdb do
  @moduledoc false

  @base_url "https://marvelcdb.com/api/public"

  def load_card(card_id) when is_integer(card_id) do
    card_id
    |> Integer.to_string()
    |> String.pad_leading(5, "0")
    |> load_card()
  end

  def load_card(card_id) when is_binary(card_id) do
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
      code: mcdb_card["code"],
      pack_code: mcdb_card["pack_code"],
      pack_name: mcdb_card["pack_name"],
      real_name: mcdb_card["real_name"],

      # Card classification
      card_type: map_card_type(mcdb_card["type_code"]),
      type_code: mcdb_card["type_code"],
      type_name: mcdb_card["type_name"],
      faction_code: mcdb_card["faction_code"],
      faction_name: mcdb_card["faction_name"],
      card_set_code: mcdb_card["card_set_code"],
      card_set_name: mcdb_card["card_set_name"],
      card_set_type_name_code: mcdb_card["card_set_type_name_code"],

      # Basic game attributes
      cost: mcdb_card["cost"],
      text: mcdb_card["text"],
      real_text: mcdb_card["real_text"],
      flavor_text: mcdb_card["flavor"],
      # Using pack_code as set_code
      set_code: mcdb_card["pack_code"],
      # Using code as card_number
      card_number: mcdb_card["code"],

      # Positioning and metadata
      position: mcdb_card["position"],
      set_position: mcdb_card["set_position"],
      quantity: mcdb_card["quantity"] || 1,
      unique: mcdb_card["is_unique"] || false,

      # Combat stats
      attack: mcdb_card["attack"],
      thwart: mcdb_card["thwart"],
      defense: mcdb_card["defense"],
      hit_points: mcdb_card["health"],
      scheme: mcdb_card["scheme"],
      recovery: mcdb_card["recover"],

      # Traits and keywords
      traits: parse_traits(mcdb_card["real_traits"] || mcdb_card["traits"]),

      # Game mechanics
      stage: mcdb_card["stage"],
      boost: mcdb_card["boost"],
      cost_per_hero: mcdb_card["cost_per_hero"] || false,
      health_per_hero: mcdb_card["health_per_hero"] || false,

      # Star ratings
      attack_star: mcdb_card["attack_star"] || false,
      thwart_star: mcdb_card["thwart_star"] || false,
      defense_star: mcdb_card["defense_star"] || false,
      health_star: mcdb_card["health_star"] || false,
      recover_star: mcdb_card["recover_star"] || false,
      scheme_star: mcdb_card["scheme_star"] || false,
      boost_star: mcdb_card["boost_star"] || false,
      threat_star: mcdb_card["threat_star"] || false,
      escalation_threat_star: mcdb_card["escalation_threat_star"] || false,

      # Threat system
      threat: mcdb_card["threat"],
      threat_fixed: mcdb_card["threat_fixed"] || false,
      base_threat: mcdb_card["base_threat"],
      base_threat_fixed: mcdb_card["base_threat_fixed"] || false,
      escalation_threat: mcdb_card["escalation_threat"],
      escalation_threat_fixed: mcdb_card["escalation_threat_fixed"] || false,

      # Card state flags
      hidden: mcdb_card["hidden"] || false,
      permanent: mcdb_card["permanent"] || false,
      double_sided: mcdb_card["double_sided"] || false,

      # External references
      octgn_id: mcdb_card["octgn_id"],
      url: mcdb_card["url"],
      imagesrc: mcdb_card["imagesrc"],
      spoiler: mcdb_card["spoiler"]
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

  defp parse_traits(nil), do: []
  defp parse_traits(""), do: []

  defp parse_traits(traits_string) when is_binary(traits_string) do
    traits_string
    |> String.split(".")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp handle_response(response) do
    case response do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: status}} -> {:error, "Unexpected status code: #{status}"}
    end
  end
end
