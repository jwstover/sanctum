defmodule SanctumWeb.Api.DeckTTSJSON do
  @moduledoc """
  Renders the versioned, names-only payload for `GET /api/decks/:id/tts`.
  Every string comes from `Sanctum.TTS.BagNames` — no image URLs, no
  mod-sourced strings beyond its bag-name output.
  """

  alias Sanctum.TTS.BagNames

  def show(%{deck: deck, side_decks: side_decks}) do
    {cards, card_unmapped} = build_cards(deck.deck_cards)
    {side_deck_names, side_deck_unmapped} = build_side_decks(side_decks)

    %{
      version: 1,
      deck: %{id: deck.id, title: deck.title, aspects: deck.aspects},
      hero: BagNames.hero_bag_names(deck.hero),
      side_decks: side_deck_names,
      cards: cards,
      unmapped: card_unmapped ++ side_deck_unmapped
    }
  end

  # Hero cards are dropped silently — they arrive via the hero `kit` bag.
  # Everything else either resolves to a pool lookup or lands in `unmapped`.
  defp build_cards(deck_cards) do
    {cards, unmapped} =
      deck_cards
      |> Enum.reject(&hero_card?/1)
      |> Enum.reduce({[], []}, fn deck_card, {cards, unmapped} ->
        case BagNames.card_lookup(deck_card.card) do
          nil ->
            {cards, [unmapped_card_label(deck_card.card) | unmapped]}

          lookup ->
            entry = Map.put(lookup, :quantity, deck_card.quantity)
            {[entry | cards], unmapped}
        end
      end)

    sorted_cards = Enum.sort_by(cards, &{&1.pool, &1.name})

    {sorted_cards, Enum.reverse(unmapped)}
  end

  defp hero_card?(%{card: %{primary_side: %{ownership: :hero}}}), do: true
  defp hero_card?(_deck_card), do: false

  defp unmapped_card_label(%{primary_side: %{name: name}}) when is_binary(name), do: name
  defp unmapped_card_label(%{code: code}), do: code

  defp build_side_decks(side_decks) do
    {names, unmapped} =
      Enum.reduce(side_decks, {[], []}, fn side_deck, {names, unmapped} ->
        case BagNames.side_deck_bag_name(side_deck) do
          nil -> {names, [side_deck.name | unmapped]}
          name -> {[name | names], unmapped}
        end
      end)

    {Enum.reverse(names), Enum.reverse(unmapped)}
  end
end
