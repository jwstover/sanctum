defmodule Sanctum.Homebrew.Validations.SetIsReportable do
  @moduledoc """
  A `SetReport` may only target a set its reporter could reach through the
  set's link: `:published` or `:unlisted`. A private (or taken-down) set
  can't be reported, and a missing one reads the same, so the check is no
  existence oracle for private sets. The set is loaded with
  `authorize?: false`, which is safe because the lookup only feeds this
  boolean. Attached with `before_action?: true`, so it runs after the create
  policy.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    with set_id when not is_nil(set_id) <- Changeset.get_attribute(changeset, :homebrew_set_id),
         {:ok, %{visibility: visibility}} when visibility in [:published, :unlisted] <-
           Ash.get(Sanctum.Homebrew.HomebrewSet, set_id, authorize?: false) do
      :ok
    else
      _ -> {:error, field: :homebrew_set_id, message: "this set can't be reported"}
    end
  end
end
