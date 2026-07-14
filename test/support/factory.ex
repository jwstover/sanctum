defmodule Sanctum.Factory do
  @moduledoc false

  defmacro create(resource, opts \\ []) do
    quote do
      action = Keyword.get(unquote(opts), :action, :create)
      count = Keyword.get(unquote(opts), :count, 1)
      override_attrs = Keyword.get(unquote(opts), :attrs, %{})
      short_name = Ash.Resource.Info.short_name(unquote(resource))
      fun = :"#{short_name}_factory"

      attrs_list =
        Enum.map(1..count, fn _ ->
          apply(Sanctum.Factory, fun, []) |> Map.merge(override_attrs)
        end)

      Enum.map(attrs_list, fn attrs ->
        unquote(resource)
        |> Ash.Changeset.for_create(action, attrs)
        |> Ash.create!(authorize?: false)
      end)
      |> case do
        [one] -> one
        many -> many
      end
    end
  end

  def card_factory do
    code = Faker.Util.format("%5d")

    %{
      base_code: code,
      code: code,
      set: "core",
      pack: "core",
      deck_limit: 3,
      unique: false,
      permanent: false,
      is_multi_sided: false
    }
  end

  def card_side_factory do
    %{
      name: Faker.Superhero.name(),
      code: Faker.Util.format("%5da"),
      side_identifier: "A",
      is_primary_side: true,
      type: :hero,
      cost: 0,
      text: Faker.Superhero.descriptor(),
      ownership: :player,
      aspect: :justice,
      attack: 2,
      thwart: 3,
      defense: 1,
      health: 10,
      recover: 3,
      hand_size: 5,
      traits: ["Avenger", "Spider"]
    }
  end

  def user_factory do
    %{
      email: Faker.Internet.email(),
      confirmed_at: DateTime.utc_now()
    }
  end

  def game_player_factory do
    %{
      form: :alter_ego,
      health: 25,
      max_health: 30,
      hand_size_mod: 0
    }
  end

  def scenario_factory do
    unique_id = :rand.uniform(100_000)

    %{
      name: "Test Scenario #{unique_id}",
      set: "test_scenario_#{unique_id}",
      recommended_modular_sets: []
    }
  end

  def game_factory do
    %{
      modular_sets: []
    }
  end
end
