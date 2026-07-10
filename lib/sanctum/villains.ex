defmodule Sanctum.Villains do
  use Ash.Domain,
    otp_app: :sanctum

  resources do
    resource Sanctum.Villains.Villain do
      define :get_villain, get_by: :id, action: :read
      define :get_by_set, args: [:set], action: :by_set
      define :create_villain, action: :create
      define :find_or_create_villain, action: :find_or_create
    end
  end
end
