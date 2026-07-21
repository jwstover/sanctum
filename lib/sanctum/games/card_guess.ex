defmodule Sanctum.Games.CardGuess do
  @moduledoc """
  Logic for the "Name That Card" guessing game (inspired by the *Stunned &
  Confused* podcast segment): the player is shown a card's flavor text and tries
  to name the card.

  This module is otherwise pure: it picks a random card that has flavor text
  (`random_guessable_card/0`, the only DB call), builds an ordered ladder of
  direct hints that narrow from release info ("it was released in Wave 5")
  down to the card's own text via `build_hints/1`, and decides whether a typed
  guess names the card via `correct?/2` (exact-normalized or a close Jaro match,
  so typos still count).
  """

  require Ash.Query

  alias Sanctum.Games.Card

  # A normalized guess this similar (0..1, via String.jaro_distance/2) to any
  # candidate name counts as correct — forgiving of typos/pluralization. Single
  # knob, tune after playtesting.
  @match_threshold 0.9

  @player_ownerships [:player, :basic, :hero]
  @encounter_ownerships [:encounter, :campaign]

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
  Flavor text as the game's prompt shows it: markup tags dropped (some
  flavors carry `<b>`/`<i>`) and the trailing speaker attribution stripped
  (see `strip_attribution/1`).
  """
  def display_flavor(nil), do: nil

  def display_flavor(flavor) when is_binary(flavor) do
    flavor |> strip_markup() |> strip_attribution()
  end

  @doc """
  Drops a trailing speaker attribution (`"…" —Domino`) from flavor text — the
  speaker is often the card's own character, which would spoil the round.

  Only an attribution *after the final closing quote* is stripped, so an
  em-dash inside the quote ("…and meet —the Hellcat!") survives untouched.
  Flavor without one comes back unchanged.
  """
  def strip_attribution(nil), do: nil

  def strip_attribution(flavor) when is_binary(flavor) do
    Regex.replace(~r/(["”])\s*[—–-]\s*[^"”]+$/u, flavor, "\\1")
  end

  @doc """
  Ordered list of `%{key: atom, text: String.t()}` hints for the card — a
  direct ladder from release info (wave, pack) through classification (player
  vs encounter, pool, exact type) down to the card itself (cost + resources,
  traits, body text). Rungs that don't apply to the card are skipped.

  The wave and pack rungs read `card.pack_ref` (+ its wave), so load them
  when hints matter — the `:guessable` read does.
  """
  def build_hints(%Card{primary_side: side} = card) do
    [
      wave_hint(card),
      pack_hint(card),
      allegiance_hint(side),
      pool_hint(card),
      type_hint(side),
      cost_resources_hint(side),
      traits_hint(side),
      set_name_hint(card),
      text_hint(side)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # 1. Release wave (curated taxonomy; not every pack belongs to one).
  defp wave_hint(%Card{pack_ref: %{wave: %{name: name}}}) when is_binary(name) and name != "",
    do: hint(:wave, "It was released in #{name}.")

  defp wave_hint(_), do: nil

  # 2. Pack — the synced catalog name, falling back to the card's pack slug.
  defp pack_hint(%Card{pack_ref: %{name: name}}) when is_binary(name) and name != "",
    do: hint(:pack, "It comes from the “#{name}” pack.")

  defp pack_hint(%Card{pack: pack}) when is_binary(pack) and pack != "",
    do: hint(:pack, "It comes from the “#{humanize_slug(pack)}” pack.")

  defp pack_hint(_), do: nil

  # 3. Allegiance — player vs encounter.
  defp allegiance_hint(%{ownership: ownership}) when ownership in @player_ownerships,
    do: hint(:allegiance, "This is a player card.")

  defp allegiance_hint(%{ownership: ownership}) when ownership in @encounter_ownerships,
    do: hint(:allegiance, "This is an encounter card.")

  defp allegiance_hint(_), do: nil

  # 4. The specific pool the card belongs to. Encounter-pool cards name their
  # set's role instead — rung 3 already said "encounter card".
  defp pool_hint(%Card{primary_side: %{type: :villain}}),
    do: hint(:pool, "This is a villain card.")

  defp pool_hint(%Card{primary_side: %{aspect: aspect}}) when not is_nil(aspect) do
    label = aspect_label(aspect)
    hint(:pool, "This is #{article(label)} #{label} card.")
  end

  defp pool_hint(%Card{primary_side: %{ownership: :hero}}),
    do: hint(:pool, "This is an identity-specific card.")

  defp pool_hint(%Card{primary_side: %{ownership: :basic}}),
    do: hint(:pool, "This is a Basic card — any deck can include it.")

  defp pool_hint(%Card{primary_side: %{ownership: :campaign}}),
    do: hint(:pool, "This is a campaign card.")

  defp pool_hint(%Card{primary_side: %{ownership: :encounter}} = card),
    do: encounter_pool_hint(card)

  defp pool_hint(_), do: nil

  # The set-role rung for encounter cards, from the synced CardSet taxonomy.
  # With no set (or an unsynced one) there's nothing rung 3 didn't already
  # say, so the rung is skipped rather than repeated.
  defp encounter_pool_hint(%Card{card_set: %{set_type: set_type}}) do
    case set_type do
      :villain -> hint(:pool, "It's part of a villain's encounter set.")
      :nemesis -> hint(:pool, "It's part of a hero's nemesis set.")
      :modular -> hint(:pool, "It's part of a modular encounter set.")
      :standard -> hint(:pool, "It's part of the Standard encounter set.")
      :expert -> hint(:pool, "It's part of the Expert encounter set.")
      :main_scheme -> hint(:pool, "It's part of a main-scheme set.")
      :hero -> hint(:pool, "It's part of a specific hero's own set.")
      :leader -> hint(:pool, "It's part of a leader set.")
      :evidence -> hint(:pool, "It's part of an evidence set.")
      _unknown -> nil
    end
  end

  defp encounter_pool_hint(_), do: nil

  # 5. The exact card type, qualified by its pool ("an Aggression event").
  # Hero identity cards skip the qualifier — "an identity-specific hero" is
  # a mouthful for the hero card itself.
  defp type_hint(%{type: nil}), do: nil

  defp type_hint(%{type: :hero}), do: hint(:type, "It's a hero card.")

  defp type_hint(side) do
    label = String.trim("#{pool_word(side)} #{String.downcase(type_label(side.type))}")
    hint(:type, "Specifically, it's #{article(label)} #{label}.")
  end

  # The pool qualifier for the type rung. Villains skip it — "a villain"
  # already says everything.
  defp pool_word(%{type: :villain}), do: ""
  defp pool_word(%{aspect: aspect}) when not is_nil(aspect), do: aspect_label(aspect)
  defp pool_word(%{ownership: :hero}), do: "identity-specific"
  defp pool_word(%{ownership: :basic}), do: "Basic"
  defp pool_word(%{ownership: :campaign}), do: "campaign"
  defp pool_word(%{ownership: :encounter}), do: "encounter"
  defp pool_word(_), do: ""

  # 6. Cost and the resource icons it provides, together.
  defp cost_resources_hint(side) do
    cost = cost_text(side.cost)
    resources = resource_counts(side)
    icons = Enum.map_join(resources, ", ", fn {label, n} -> "#{n} #{label}" end)

    case {cost, resources} do
      {nil, []} ->
        nil

      {cost, []} ->
        hint(:cost, "Its resource cost is #{cost}.")

      {nil, resources} ->
        hint(:cost, "It provides #{icons} #{icon_word(resources)}.")

      {cost, resources} ->
        hint(:cost, "It costs #{cost} and provides #{icons} #{icon_word(resources)}.")
    end
  end

  # MarvelCDB encodes a printed X cost as -1.
  defp cost_text(-1), do: "X"
  defp cost_text(cost) when is_integer(cost), do: Integer.to_string(cost)
  defp cost_text(_), do: nil

  defp resource_counts(side) do
    [
      {"energy", side.resource_energy_count},
      {"physical", side.resource_physical_count},
      {"mental", side.resource_mental_count},
      {"wild", side.resource_wild_count}
    ]
    |> Enum.filter(fn {_label, n} -> is_integer(n) and n > 0 end)
  end

  defp icon_word(resources) do
    total = resources |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    if total == 1, do: "resource icon", else: "resource icons"
  end

  # 7. Traits.
  defp traits_hint(%{traits: traits}) when is_list(traits) and traits != [],
    do: hint(:traits, "Traits: #{Enum.join(traits, ", ")}.")

  defp traits_hint(_), do: nil

  # 8. For scenario cards, the set the card belongs to — the villain or
  # modular set by name. Skipped when the set name would hand over the card's
  # own name (the villain card in its self-titled set).
  defp set_name_hint(%Card{card_set: %{name: set_name, set_type: set_type}, primary_side: side})
       when is_binary(set_name) and set_name != "" do
    cond do
      side.ownership not in @encounter_ownerships -> nil
      names_overlap?(set_name, side.name) -> nil
      true -> hint(:set_name, "It belongs to the “#{set_name}” #{set_kind(set_type)}.")
    end
  end

  defp set_name_hint(_), do: nil

  defp set_kind(:villain), do: "villain set"
  defp set_kind(:modular), do: "modular set"
  defp set_kind(:nemesis), do: "nemesis set"
  defp set_kind(_), do: "set"

  defp names_overlap?(set_name, card_name) do
    a = normalize(set_name)
    b = normalize(card_name)
    a != "" and b != "" and (String.contains?(a, b) or String.contains?(b, a))
  end

  # 9. The card's own rules text, name redacted — the final giveaway.
  defp text_hint(%{text: text, name: name}) when is_binary(text) and text != "" do
    hint(:text, "Its text reads: “#{text |> strip_markup() |> redact_name(name)}”")
  end

  defp text_hint(_), do: nil

  # MarvelCDB text carries simple HTML tags (<b>, <i>, <em>); hints render as
  # plain text, so drop them and collapse the whitespace they leave behind.
  defp strip_markup(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp redact_name(text, name) when is_binary(name) and name != "" do
    Regex.replace(~r/#{Regex.escape(name)}/iu, text, "____")
  end

  defp redact_name(text, _name), do: text

  defp hint(key, text), do: %{key: key, text: text}

  defp type_label(type),
    do: type |> to_string() |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

  defp aspect_label(aspect), do: aspect |> to_string() |> String.capitalize()

  defp humanize_slug(slug),
    do: slug |> String.split(~r/[_\s]+/, trim: true) |> Enum.map_join(" ", &String.capitalize/1)

  defp article(word) do
    if String.downcase(String.first(word)) in ~w(a e i o u), do: "an", else: "a"
  end
end
