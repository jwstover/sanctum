defmodule Sanctum.Decks.HandSimulatorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Decks.HandSimulator

  defp view(card_id, qty, opts \\ []) do
    %{
      card_id: card_id,
      qty: qty,
      name: "Card #{card_id}",
      cost: 1,
      cost_value: 1,
      type: :ally,
      hero?: false,
      permanent: Keyword.get(opts, :permanent, false),
      aspect_key: :justice,
      aspect_bg: "bg-aspect-justice",
      pips: [],
      image_url: nil,
      gradient_from: nil,
      gradient_to: nil,
      max: 3,
      owned: nil
    }
  end

  describe "new/2" do
    test "draws exactly hand_size cards" do
      card_views = [view("a", 3), view("b", 3), view("c", 3)]
      state = HandSimulator.new(card_views, 5)

      assert length(state.hand) == 5
      assert state.hand_size == 5
      assert state.mulliganed? == false
      assert state.discard == []
    end

    test "excludes permanent cards from the draw deck" do
      card_views = [view("a", 3), view("perm", 3, permanent: true)]
      state = HandSimulator.new(card_views, 5)

      refute Enum.any?(state.hand ++ state.pile, &(&1.card_id == "perm"))
    end

    test "excludes cards with qty <= 0" do
      card_views = [view("a", 3), view("zero", 0)]
      state = HandSimulator.new(card_views, 3)

      refute Enum.any?(state.hand ++ state.pile, &(&1.card_id == "zero"))
    end

    test "expands qty into that many individually-selectable copies" do
      card_views = [view("a", 3)]
      state = HandSimulator.new(card_views, 3)

      copy_ids = Enum.map(state.hand, & &1.copy_id)
      assert length(copy_ids) == 3
      assert length(Enum.uniq(copy_ids)) == 3
      assert Enum.all?(copy_ids, &String.starts_with?(&1, "a-"))
    end

    test "gracefully handles a pile smaller than the hand size" do
      card_views = [view("a", 2)]
      state = HandSimulator.new(card_views, 5)

      assert length(state.hand) == 2
      assert state.pile == []
    end
  end

  describe "mulligan/2" do
    test "draws exactly as many cards as were discarded" do
      card_views = [view("a", 10)]
      state = HandSimulator.new(card_views, 5)
      [c1, c2 | _] = state.hand

      new_state = HandSimulator.mulligan(state, [c1.copy_id, c2.copy_id])

      assert length(new_state.hand) == 5
      assert new_state.mulliganed? == true
    end

    test "keeps the unselected cards and draws replacements off the pile" do
      card_views = for id <- ~w(a b c d e f g h), do: view(id, 1)
      state = HandSimulator.new(card_views, 5)
      [c1, c2 | kept] = state.hand
      pile_ids = MapSet.new(state.pile, & &1.copy_id)

      new_state = HandSimulator.mulligan(state, [c1.copy_id, c2.copy_id])
      new_ids = MapSet.new(new_state.hand, & &1.copy_id)

      # The three untouched cards stay put...
      assert MapSet.subset?(MapSet.new(kept, & &1.copy_id), new_ids)
      # ...and the two replacements came off the top of the pile.
      drawn = MapSet.difference(new_ids, MapSet.new(kept, & &1.copy_id))
      assert MapSet.size(drawn) == 2
      assert MapSet.subset?(drawn, pile_ids)
    end

    test "discarded cards never reappear in the hand" do
      card_views = [view("a", 10)]
      state = HandSimulator.new(card_views, 5)
      [c1 | _] = state.hand

      new_state = HandSimulator.mulligan(state, [c1.copy_id])

      refute Enum.any?(new_state.hand, &(&1.copy_id == c1.copy_id))
      assert Enum.any?(new_state.discard, &(&1.copy_id == c1.copy_id))
    end

    test "discarded cards are not shuffled back into the pile" do
      card_views = [view("a", 6)]
      state = HandSimulator.new(card_views, 5)
      [c1 | _] = state.hand

      new_state = HandSimulator.mulligan(state, [c1.copy_id])

      refute Enum.any?(new_state.pile, &(&1.copy_id == c1.copy_id))
    end

    test "a second mulligan is a no-op" do
      card_views = [view("a", 10)]
      state = HandSimulator.new(card_views, 5)
      [c1 | _] = state.hand

      once = HandSimulator.mulligan(state, [c1.copy_id])
      twice = HandSimulator.mulligan(once, [Enum.at(once.hand, 0).copy_id])

      assert twice == once
    end

    test "an empty selection is a no-op" do
      card_views = [view("a", 10)]
      state = HandSimulator.new(card_views, 5)

      assert HandSimulator.mulligan(state, []) == state
    end

    test "pile smaller than the discarded count doesn't crash" do
      card_views = [view("a", 5)]
      state = HandSimulator.new(card_views, 5)
      # Pile is empty (5 drawn out of 5); discard the whole hand.
      assert state.pile == []

      copy_ids = Enum.map(state.hand, & &1.copy_id)
      new_state = HandSimulator.mulligan(state, copy_ids)

      assert new_state.hand == []
      assert length(new_state.discard) == 5
      assert new_state.mulliganed? == true
    end
  end
end
