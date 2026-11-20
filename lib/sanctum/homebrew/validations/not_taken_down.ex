defmodule Sanctum.Homebrew.Validations.NotTakenDown do
  @moduledoc """
  A `HomebrewSet` an admin has taken down (`taken_down_at` set) can't be made
  `:unlisted` or `:published` again until an admin restores it
  (`:restore`). Making it `:private` stays allowed.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    if Changeset.get_attribute(changeset, :visibility) in [:unlisted, :published] and
         not is_nil(changeset.data.taken_down_at) do
      {:error,
       field: :visibility,
       message: "this set was taken down by a moderator and can't be shared until it's restored"}
    else
      :ok
    end
  end
end
