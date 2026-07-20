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
  `:primary_side` loaded. `aspects` is the deck's chosen aspect list (empty =
  basic deck). `signature_cards` are the hero's signature-set cards (ownership
  `:hero`), each expected at exactly `deck_limit` copies.
  """
  @spec issues([map()], [atom()], [map()]) :: [Issue.t()]
  def issues(entries, aspects, signature_cards)
      when is_list(entries) and is_list(aspects) and is_list(signature_cards) do
    size_issues(entries) ++
      hero_set_issues(entries, signature_cards) ++
      copy_limit_issues(entries) ++
      aspect_issues(entries, aspects)
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

  defp aspect_issues(entries, aspects) do
    for entry <- entries,
        ownership(entry) == :player,
        aspect = primary_side(entry).aspect,
        not is_nil(aspect),
        aspect not in aspects do
      %Issue{
        code: :off_aspect,
        severity: :warning,
        message: "#{entry_name(entry)} is #{aspect_label(aspect)}, outside this deck's aspects",
        card_id: card(entry).id
      }
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

  defp aspect_label(:pool), do: "'Pool"
  defp aspect_label(aspect), do: aspect |> to_string() |> String.capitalize()
end
