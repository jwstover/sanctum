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
        |> Ash.create!()
      end)
      |> case do
        [one] -> one
        many -> many
      end
    end
  end

  def card_factory do
    %{
      name: Faker.Superhero.name(),
      type: :hero,
      cost: 0,
      text: Faker.Superhero.descriptor(),
      set: "core",
      code: Faker.Util.format("%5d"),
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
end
