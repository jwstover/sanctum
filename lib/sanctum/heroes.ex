defmodule Sanctum.Heroes do
  use Ash.Domain,
    otp_app: :sanctum

  resources do
    resource Sanctum.Heroes.Hero do
      define :get_by_set, get_by: :set, action: :read
      define :create_hero, action: :create
      define :find_or_create_hero, action: :find_or_create
    end
  end

  @doc """
  `set -> {primary_color, secondary_color}` for every hero, for resolving card
  border gradients. Heroes without a stored palette map to `{nil, nil}`.
  """
  def hero_color_map do
    Sanctum.Heroes.Hero
    |> Ash.read!()
    |> Map.new(fn h -> {h.set, {h.primary_color, h.secondary_color}} end)
  end
end
