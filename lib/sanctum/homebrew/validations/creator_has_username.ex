defmodule Sanctum.Homebrew.Validations.CreatorHasUsername do
  @moduledoc """
  Publishing a `HomebrewSet` needs its *creator* to have claimed a username:
  published work is attributed by that handle, and the public URL
  (`/custom/@username/slug`) is built from it. Checked on every move to
  `:published`, not only the first, because the URL needs it each time.

  It checks the creator, not the actor, because the admin bypass may publish
  on someone else's behalf. The creator is loaded with `authorize?: false`,
  which is safe because the lookup only feeds this boolean. Attached with
  `before_action?: true`, so it runs only after the update policy has passed.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    if Changeset.get_attribute(changeset, :visibility) == :published and
         not creator_has_username?(Changeset.get_attribute(changeset, :creator_id)) do
      {:error,
       field: :visibility,
       message:
         "claim a username first — published sets are credited to it and use it in their URL"}
    else
      :ok
    end
  end

  defp creator_has_username?(nil), do: false

  defp creator_has_username?(creator_id) do
    case Ash.get(Sanctum.Accounts.User, creator_id, authorize?: false) do
      {:ok, %{username: username}} -> not is_nil(username)
      _not_found -> false
    end
  end
end
