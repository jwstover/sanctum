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
end
