defmodule Sanctum.Decks.Legality do
  @moduledoc """
  Advisory deck-legality checks.

  Issues are informational only — Sanctum never blocks a save on them.
  Identity cards carry special deckbuilding rules the app doesn't model
  (multi-aspect heroes, card-pool restrictions), so players stay the final
  authority; the UI just surfaces what looks off.

  `Card.deck_limit` mirrors MarvelCDB's pack `quantity`, which for a few
  cards differs from the printed "Limit 1 per deck" text (core Energy ships
  4 copies), so the deck-limit check is knowingly approximate there.
  """

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
  """
  @spec issues([map()], [map()]) :: [Issue.t()]
  def issues(entries, signature_cards)
      when is_list(entries) and is_list(signature_cards) do
    size_issues(entries) ++
      hero_set_issues(entries, signature_cards) ++
      copy_limit_issues(entries) ++
      multi_aspect_issues(entries)
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

  defp copy_limit_issues(entries) do
    Enum.flat_map(entries, fn entry ->
      c = card(entry)
      qty = quantity(entry)
      limit = c.deck_limit || 1

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
  # or experimental deck may want to — but surface it as advisory when more than
  # one aspect is represented.
  defp multi_aspect_issues(entries) do
    case aspects_from_entries(entries) do
      aspects when length(aspects) > 1 ->
        labels = Enum.map_join(aspects, ", ", &aspect_label/1)

        [
          %Issue{
            code: :multi_aspect,
            severity: :warning,
            message: "Deck combines #{length(aspects)} aspects (#{labels})"
          }
        ]

      _one_or_none ->
        []
    end
  end

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
