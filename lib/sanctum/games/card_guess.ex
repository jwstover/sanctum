defmodule Sanctum.Games.CardGuess do
  @moduledoc """
  Logic for the "Name That Card" guessing game (inspired by the *Stunned &
  Confused* podcast segment): the player is shown a card's flavor text and tries
  to name the card.

  This module is otherwise pure: it picks a random card that has flavor text
  (`random_guessable_card/0`, the only DB call), builds an ordered ladder of
  hints that narrow from broad ("it's a player card") to specific ("it comes
  from the Spider-Man pack") via `build_hints/1`, and decides whether a typed
  guess names the card via `correct?/2` (exact-normalized or a close Jaro match,
  so typos still count).
  """

  require Ash.Query

  alias Sanctum.Games.{Card, Stat}

  # A normalized guess this similar (0..1, via String.jaro_distance/2) to any
  # candidate name counts as correct — forgiving of typos/pluralization. Single
  # knob, tune after playtesting.
  @match_threshold 0.9

  @player_ownerships [:player, :basic, :hero]
  @encounter_ownerships [:encounter, :campaign]
  @character_types [:hero, :alter_ego, :ally, :minion, :villain]
  @scheme_types [:main_scheme, :side_scheme]

  @doc """
  Fetches a random card that has flavor text, with its primary side loaded.
  Returns `nil` when no guessable cards exist.
  """
  def random_guessable_card do
    count =
      Card
      |> Ash.Query.for_read(:guessable)
      |> Ash.read!(page: [limit: 1, offset: 0, count: true])
      |> Map.get(:count)

    if is_integer(count) and count > 0 do
      offset = :rand.uniform(count) - 1

      Card
      |> Ash.Query.for_read(:guessable)
      |> Ash.read!(page: [limit: 1, offset: offset])
      |> Map.get(:results)
      |> List.first()
    end
  end

  @doc """
  Whether `guess` names the card — a case/punctuation-insensitive exact match
  or a Jaro similarity at/above `#{@match_threshold}` against the name,
  subname, or "name subname".
  """
  def correct?(guess, %Card{primary_side: side}) do
    normalized = normalize(guess)

    normalized != "" and
      side
      |> candidates()
      |> Enum.map(&normalize/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.any?(fn candidate ->
        candidate == normalized or String.jaro_distance(normalized, candidate) >= @match_threshold
      end)
  end

  defp candidates(%{name: name, subname: subname}), do: [name, subname, join_name(name, subname)]

  defp join_name(name, subname)
       when is_binary(name) and is_binary(subname) and subname != "",
       do: name <> " " <> subname

  defp join_name(_, _), do: nil

  @doc """
  Lowercases, strips a leading "the ", drops punctuation, and collapses
  whitespace so "The Vision!" and "vision" compare equal.
  """
  def normalize(nil), do: ""

  def normalize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.trim()
    |> String.replace_prefix("the ", "")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc """
  Ordered list of `%{key: atom, text: String.t()}` hints for the card, broadest
  first. Rungs that don't apply to the card are skipped, so a player card and an
  encounter card each get a sensible ~10-hint ladder.
  """
  def build_hints(%Card{primary_side: side} = card) do
    [
      allegiance_hint(side),
      nature_hint(side),
      aspect_hint(side),
      type_hint(side),
      traits_hint(side),
      cost_hint(side),
      resources_hint(side),
      stats_hint(side),
      uniqueness_hint(card),
      set_hint(card),
      name_shape_hint(side)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # 1. Allegiance — player vs encounter.
  defp allegiance_hint(%{ownership: ownership}) when ownership in @player_ownerships,
    do: hint(:allegiance, "This is a player card.")

  defp allegiance_hint(%{ownership: ownership}) when ownership in @encounter_ownerships,
    do: hint(:allegiance, "This is an encounter card.")

  defp allegiance_hint(_), do: nil

  # 2. Broad nature — character / scheme / support-style.
  defp nature_hint(%{type: type}) when type in @character_types,
    do: hint(:nature, "It's a character card — something with hit points.")

  defp nature_hint(%{type: type}) when type in @scheme_types,
    do: hint(:nature, "It's a scheme.")

  defp nature_hint(%{type: type}) when not is_nil(type),
    do: hint(:nature, "It's not a character or a scheme — more of a support-style card.")

  defp nature_hint(_), do: nil

  # 3. Aspect / origin.
  defp aspect_hint(%{aspect: aspect}) when not is_nil(aspect),
    do: hint(:aspect, "Its aspect is #{aspect_label(aspect)}.")

  defp aspect_hint(%{ownership: :hero}), do: hint(:aspect, "It's a hero signature card.")

  defp aspect_hint(%{ownership: :basic}),
    do: hint(:aspect, "It's a Basic card — any deck can include it.")

  defp aspect_hint(_), do: nil

  # 4. Exact card type.
  defp type_hint(%{type: type}) when not is_nil(type) do
    label = type_label(type)
    hint(:type, "It's #{article(label)} #{label}.")
  end

  defp type_hint(_), do: nil

  # 5. Traits.
  defp traits_hint(%{traits: traits}) when is_list(traits) and traits != [],
    do: hint(:traits, "Traits: #{Enum.join(traits, ", ")}.")

  defp traits_hint(_), do: nil

  # 6. Resource cost.
  defp cost_hint(%{cost: cost}) when is_integer(cost),
    do: hint(:cost, "Its resource cost is #{cost}.")

  defp cost_hint(_), do: nil

  # 7. Resource icons it provides.
  defp resources_hint(side) do
    [
      {"energy", side.resource_energy_count},
      {"physical", side.resource_physical_count},
      {"mental", side.resource_mental_count},
      {"wild", side.resource_wild_count}
    ]
    |> Enum.flat_map(fn {label, n} ->
      if is_integer(n) and n > 0, do: ["#{n} #{label}"], else: []
    end)
    |> case do
      [] -> nil
      list -> hint(:resources, "Resource icons it provides: #{Enum.join(list, ", ")}.")
    end
  end

  # 8. Stats (character combat stats or scheme threat).
  defp stats_hint(side) do
    [
      {"ATK", side.attack},
      {"THW", side.thwart},
      {"DEF", side.defense},
      {"HP", side.health},
      {"REC", side.recover},
      {"Starting threat", side.base_threat},
      {"Max threat", side.max_threat}
    ]
    |> Enum.flat_map(&stat_pair/1)
    |> case do
      [] -> nil
      list -> hint(:stats, "Stats — #{Enum.join(list, ", ")}.")
    end
  end

  defp stat_pair({label, %Stat{value: value}}) when is_integer(value), do: ["#{label} #{value}"]
  defp stat_pair(_), do: []

  # 9. Uniqueness / deck limit.
  defp uniqueness_hint(%{unique: true}), do: hint(:uniqueness, "This card is unique.")

  defp uniqueness_hint(%{deck_limit: limit}) when is_integer(limit) and limit > 0,
    do: hint(:uniqueness, "It's not unique — a deck can include up to #{limit} #{copies(limit)}.")

  defp uniqueness_hint(_), do: nil

  # 10. Set / pack it comes from.
  defp set_hint(%{set: set}) when is_binary(set) and set != "",
    do: hint(:set, "It comes from the “#{humanize_slug(set)}” set.")

  defp set_hint(%{pack: pack}) when is_binary(pack) and pack != "",
    do: hint(:set, "It comes from the “#{humanize_slug(pack)}” pack.")

  defp set_hint(_), do: nil

  # 11. Name shape — the last-resort giveaway.
  defp name_shape_hint(%{name: name}) when is_binary(name) and name != "" do
    words = name |> String.split(~r/\s+/, trim: true) |> length()
    first = name |> String.trim() |> String.first() |> String.upcase()
    hint(:name_shape, "The name has #{words} #{word_word(words)} and starts with “#{first}”.")
  end

  defp name_shape_hint(_), do: nil

  defp hint(key, text), do: %{key: key, text: text}

  defp type_label(type),
    do: type |> to_string() |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

  defp aspect_label(aspect), do: aspect |> to_string() |> String.capitalize()

  defp humanize_slug(slug),
    do: slug |> String.split(~r/[_\s]+/, trim: true) |> Enum.map_join(" ", &String.capitalize/1)

  defp article(word) do
    if String.downcase(String.first(word)) in ~w(a e i o u), do: "an", else: "a"
  end

  defp copies(1), do: "copy"
  defp copies(_), do: "copies"

  defp word_word(1), do: "word"
  defp word_word(_), do: "words"
end
