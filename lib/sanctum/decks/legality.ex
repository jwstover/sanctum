defmodule Sanctum.Decks.Legality do
  @moduledoc """
  Advisory deck-legality checks.

  Issues are informational only — Sanctum never blocks a save on them.
  Players stay the final authority; the UI just surfaces what looks off.

  A few identity cards break the standard template (multi-aspect heroes,
  single-copy decks, off-aspect allowances). Those are spelled out per hero in
  `Sanctum.Decks.HeroRules` and threaded in via the deck's hero `set`; the
  checks below honor them so the advisories don't cry wolf for those heroes.

  `Card.deck_limit` mirrors MarvelCDB's pack `quantity`, which for a few
  cards differs from the printed "Limit 1 per deck" text (core Energy ships
  4 copies), so the deck-limit check is knowingly approximate there.
  """

  alias Sanctum.Decks.HeroRules

  defmodule Issue do
    @moduledoc "A single advisory finding about a deck."

    defstruct [:code, :severity, :message, :card_id]

    @type t :: %__MODULE__{
            code: atom(),
            severity: :error | :warning,
            message: String.t(),
            card_id: term() | nil
          }
  end

  @min_size 40
  @max_size 50

  @doc """
  Advisory issues for a deck's card entries.

  `entries` accepts loaded `DeckCard` structs or plain maps shaped like
  `%{card: card, quantity: n, ignore_deck_limit: bool}` where `card` has its
  `:primary_side` loaded. `signature_cards` are the hero's signature-set cards
  (ownership `:hero`), each expected at exactly `deck_limit` copies.

  Each rule is a self-contained `*_issues/1|2` function returning a list of
  `Issue`s; this is the single entrypoint that composes them. To add a rule,
  write one function and append it here. Nothing here ever blocks a save.

  The deck's aspects are not passed in — they're inferred from the cards
  themselves (see `aspects_from_entries/1`), so there is no separate "chosen
  aspect" to validate against.

  `hero_set` is the deck's hero `set`; it selects the hero's
  `Sanctum.Decks.HeroRules` so the aspect and copy-limit checks respect any
  special deckbuilding exception. Omit it (or pass `nil`) for the standard
  template.
  """
  @spec issues([map()], [map()], String.t() | nil) :: [Issue.t()]
  def issues(entries, signature_cards, hero_set \\ nil)
      when is_list(entries) and is_list(signature_cards) do
    rules = HeroRules.for_set(hero_set)

    size_issues(entries) ++
      hero_set_issues(entries, signature_cards) ++
      copy_limit_issues(entries, rules) ++
      multi_aspect_issues(entries, rules)
  end

  @doc """
  The distinct aspects a deck draws from, inferred from its player cards.

  Sanctum has no up-front aspect choice: a deck's aspect(s) are simply the
  aspects of the player-owned aspect cards in it. Adding the first aspect card
  gives the deck its aspect; removing every card of that aspect and adding a
  different one flips it. Returned sorted so callers can compare/persist a
  canonical value. Hero and basic cards (no aspect) never contribute.
  """
  @spec aspects_from_entries([map()]) :: [String.t()]
  def aspects_from_entries(entries) when is_list(entries) do
    entries
    |> Enum.filter(&(ownership(&1) == :player and quantity(&1) > 0))
    |> Enum.map(&primary_side(&1).aspect)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp size_issues(entries) do
    total =
      entries
      |> Enum.reject(&card(&1).permanent)
      |> Enum.reduce(0, &(quantity(&1) + &2))

    cond do
      total < @min_size ->
        [
          %Issue{
            code: :too_few,
            severity: :warning,
            message: "Deck has #{total} cards (minimum #{@min_size})"
          }
        ]

      total > @max_size ->
        [
          %Issue{
            code: :too_many,
            severity: :warning,
            message: "Deck has #{total} cards (maximum #{@max_size})"
          }
        ]

      true ->
        []
    end
  end

  defp hero_set_issues(entries, signature_cards) do
    hero_quantities =
      entries
      |> Enum.filter(&(ownership(&1) == :hero))
      |> Map.new(&{card(&1).id, quantity(&1)})

    expected = Map.new(signature_cards, &{&1.id, &1.deck_limit || 1})

    incomplete =
      for sig <- signature_cards,
          have = Map.get(hero_quantities, sig.id, 0),
          want = expected[sig.id],
          have < want do
        %Issue{
          code: :hero_set_incomplete,
          severity: :error,
          message: "#{card_name(sig)} needs #{want} #{copies(want)} (has #{have})",
          card_id: sig.id
        }
      end

    extra =
      for entry <- entries,
          ownership(entry) == :hero,
          want = Map.get(expected, card(entry).id, 0),
          quantity(entry) > want do
        %Issue{
          code: :hero_set_extra,
          severity: :error,
          message: "#{entry_name(entry)} exceeds the hero set (#{quantity(entry)} > #{want})",
          card_id: card(entry).id
        }
      end

    incomplete ++ extra
  end

  defp copy_limit_issues(entries, rules) do
    Enum.flat_map(entries, fn entry ->
      c = card(entry)
      qty = quantity(entry)
      limit = effective_limit(entry, c, rules)

      cond do
        c.unique and qty > 1 ->
          [
            %Issue{
              code: :unique_dup,
              severity: :error,
              message: "#{entry_name(entry)} is unique (max 1 copy, has #{qty})",
              card_id: c.id
            }
          ]

        qty > limit and not ignore_deck_limit?(entry) ->
          [
            %Issue{
              code: :deck_limit_exceeded,
              severity: :error,
              message: "#{entry_name(entry)} exceeds its deck limit (#{qty} > #{limit})",
              card_id: c.id
            }
          ]

        true ->
          []
      end
    end)
  end

  # Standard decks draw from a single aspect. We don't forbid mixing — a custom
  # or experimental deck may want to — but surface it as advisory when the deck
  # draws from more aspects than its hero is allowed.
  #
  # `rules.max_aspects` covers heroes built to span aspects (Spider-Woman: 2,
  # Adam Warlock: 4). Others keep one chosen aspect but may include specific
  # off-aspect cards (Gamora's events, Cyclops's X-Men allies, Maria Hill's
  # S.H.I.E.L.D. supports) — those extra aspects are expected, so we check the
  # allowance rather than warn.
  defp multi_aspect_issues(entries, rules) do
    aspects = aspects_from_entries(entries)

    cond do
      length(aspects) <= rules.max_aspects ->
        equal_aspect_issues(entries, aspects, rules)

      rules.off_aspect_allowance ->
        off_aspect_allowance_issues(entries, aspects, rules.off_aspect_allowance)

      true ->
        [multi_aspect_warning(aspects)]
    end
  end

  defp multi_aspect_warning(aspects) do
    labels = Enum.map_join(aspects, ", ", &aspect_label/1)

    %Issue{
      code: :multi_aspect,
      severity: :warning,
      message: "Deck combines #{length(aspects)} aspects (#{labels})"
    }
  end

  # Spider-Woman / Adam Warlock must contribute equal card counts per aspect.
  # Advisory only — flag when the chosen aspects are lopsided.
  defp equal_aspect_issues(_entries, aspects, %{equal_aspects: false}) when is_list(aspects),
    do: []

  defp equal_aspect_issues(_entries, aspects, _rules) when length(aspects) <= 1, do: []

  defp equal_aspect_issues(entries, aspects, _rules) do
    counts = aspect_counts(entries, aspects)

    if counts |> Map.values() |> Enum.uniq() |> length() > 1 do
      detail = Enum.map_join(aspects, ", ", &"#{aspect_label(&1)} #{Map.get(counts, &1, 0)}")

      [
        %Issue{
          code: :unequal_aspects,
          severity: :warning,
          message: "Aspects should have equal card counts (#{detail})"
        }
      ]
    else
      []
    end
  end

  # Heroes with one chosen aspect plus an off-aspect card allowance (Gamora,
  # Cyclops, Maria Hill). Treat the largest aspect as the chosen one; every
  # other-aspect player card must fit the allowance's trait/type, and any card
  # limit must hold. Advisory only.
  defp off_aspect_allowance_issues(entries, aspects, spec) do
    chosen = chosen_aspect(entries, aspects)
    off = off_aspect_entries(entries, aspects, chosen)

    cond do
      not Enum.all?(off, &qualifies_for_allowance?(&1, spec)) ->
        [
          %Issue{
            code: :off_aspect_not_allowed,
            severity: :warning,
            message: "Off-aspect cards must be #{spec.label}"
          }
        ]

      over_allowance_limit?(off, spec) ->
        [
          %Issue{
            code: :off_aspect_over_limit,
            severity: :warning,
            message: "Too many off-aspect #{spec.label} (max #{spec.limit})"
          }
        ]

      true ->
        []
    end
  end

  # The chosen aspect is whichever contributes the most cards — off-aspect
  # allowances ride on top of a single dominant aspect.
  defp chosen_aspect(entries, aspects) do
    {chosen, _count} =
      entries
      |> aspect_counts(aspects)
      |> Enum.max_by(fn {_aspect, n} -> n end)

    chosen
  end

  defp off_aspect_entries(entries, aspects, chosen) do
    Enum.filter(entries, fn entry ->
      side = primary_side(entry)

      ownership(entry) == :player and quantity(entry) > 0 and
        is_binary(side.aspect) and side.aspect in aspects and side.aspect != chosen
    end)
  end

  defp qualifies_for_allowance?(entry, spec) do
    side = primary_side(entry)

    side.type in spec.types and
      traits_ok?(side.traits || [], Map.get(spec, :traits)) and
      resource_ok?(side, Map.get(spec, :resource))
  end

  # A trait-less allowance (e.g. Cable's player side schemes) constrains by type
  # only, so any traits qualify.
  defp traits_ok?(_card_traits, allowed) when allowed in [nil, []], do: true
  defp traits_ok?(card_traits, allowed), do: trait_match?(card_traits, allowed)

  # Wonder Man's allowance requires a printed resource pip; other allowances
  # don't constrain resources. Static field keys (not interpolated atoms) keep
  # Sobelow happy and the lookup total.
  defp resource_ok?(_side, nil), do: true
  defp resource_ok?(side, :energy), do: printed?(side, :resource_energy_count)
  defp resource_ok?(side, :physical), do: printed?(side, :resource_physical_count)
  defp resource_ok?(side, :mental), do: printed?(side, :resource_mental_count)
  defp resource_ok?(side, :wild), do: printed?(side, :resource_wild_count)

  defp printed?(side, field), do: (Map.get(side, field) || 0) > 0

  # Traits are stored inconsistently (e.g. "S.H.I.E.L.D" vs "S.H.I.E.L.D."), so
  # compare case-insensitively with any trailing period trimmed.
  defp trait_match?(card_traits, allowed) do
    normalized = MapSet.new(card_traits, &normalize_trait/1)
    Enum.any?(allowed, &MapSet.member?(normalized, normalize_trait(&1)))
  end

  defp normalize_trait(trait) do
    trait |> to_string() |> String.downcase() |> String.trim_trailing(".")
  end

  defp over_allowance_limit?(off, spec) do
    case Map.get(spec, :limit) do
      nil ->
        false

      limit ->
        count =
          case Map.get(spec, :limit_by, :copies) do
            :titles -> off |> Enum.map(&card(&1).id) |> Enum.uniq() |> length()
            :copies -> off |> Enum.map(&quantity/1) |> Enum.sum()
          end

        count > limit
    end
  end

  # Per-aspect total quantities across the deck's player aspect cards. A nil
  # aspect is never in `allowed` (which holds only the binary aspect strings),
  # so basic/hero cards fall out in the filter.
  defp aspect_counts(entries, aspects) do
    allowed = MapSet.new(aspects)

    entries
    |> Enum.filter(fn entry ->
      ownership(entry) == :player and quantity(entry) > 0 and
        MapSet.member?(allowed, primary_side(entry).aspect)
    end)
    |> Enum.reduce(%{}, fn entry, acc ->
      Map.update(acc, primary_side(entry).aspect, quantity(entry), &(&1 + quantity(entry)))
    end)
  end

  # A player/basic card's copy limit, honoring Adam Warlock's single-copy rule.
  defp effective_limit(entry, card, %{single_copy: true}) when is_map(card) do
    if ownership(entry) in [:player, :basic], do: 1, else: card.deck_limit || 1
  end

  defp effective_limit(_entry, card, _rules), do: card.deck_limit || 1

  defp card(entry), do: Map.fetch!(entry, :card)
  defp quantity(entry), do: Map.fetch!(entry, :quantity)
  defp ignore_deck_limit?(entry), do: Map.get(entry, :ignore_deck_limit, false)

  defp primary_side(entry), do: card(entry).primary_side

  defp ownership(entry) do
    case primary_side(entry) do
      %{ownership: ownership} -> ownership
      _missing -> nil
    end
  end

  defp entry_name(entry) do
    case primary_side(entry) do
      %{name: name} when is_binary(name) -> name
      _missing -> "Card #{card(entry).code}"
    end
  end

  defp card_name(%{primary_side: %{name: name}}) when is_binary(name), do: name
  defp card_name(card), do: "Card #{card.code}"

  defp copies(1), do: "copy"
  defp copies(_n), do: "copies"

  defp aspect_label("pool"), do: "'Pool"
  defp aspect_label(aspect), do: aspect |> to_string() |> String.capitalize()
end
