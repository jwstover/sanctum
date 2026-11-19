defmodule Sanctum.Homebrew.Changes.RecordPublishAttestation do
  @moduledoc """
  The first publish of a `HomebrewSet` needs the creator's publish
  attestation: "I'm allowed to distribute this, publicly, under my name."
  This is a separate claim from the project's upload attestation ("I'm allowed
  to store this"). It is dated and scoped to this set, so it is the one that
  carries weight in a takedown.

  Moving to `:published` while `attested_at` is nil requires the `:attest`
  argument to be true. When it is, `attestation` and `attested_at` are stamped.
  Later re-publishes, after an unpublish, keep the original attestation and
  don't ask again. No other action writes these attributes.

  Runs in `before_action`, after the update policy.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      cond do
        Changeset.get_attribute(changeset, :visibility) != :published ->
          changeset

        not is_nil(changeset.data.attested_at) ->
          changeset

        Changeset.get_argument(changeset, :attest) == true ->
          changeset
          |> Changeset.force_change_attribute(:attestation, true)
          |> Changeset.force_change_attribute(:attested_at, DateTime.utc_now())

        true ->
          Changeset.add_error(changeset,
            field: :attest,
            message: "confirm you may publish this set before publishing it"
          )
      end
    end)
  end
end
