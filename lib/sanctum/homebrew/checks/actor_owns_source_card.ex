defmodule Sanctum.Homebrew.Checks.ActorOwnsSourceCard do
  @moduledoc """
  Policy check for CardAlt's `:declare_custom`: the `:source_card_id`
  argument must name a custom card in one of the actor's projects. Resolved
  by hand — filter checks can't see the source card (the alt row doesn't
  exist yet), and policies run before `before_action` hooks, so the change
  module's attribute writes are invisible here; arguments are not. The
  `authorize?: false` get never returns data to the caller — it only feeds
  the boolean.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the source card belongs to one of the actor's projects"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    with card_id when not is_nil(card_id) <-
           Ash.Changeset.get_argument(changeset, :source_card_id),
         {:ok, card} <-
           Ash.get(Sanctum.Games.Card, card_id, authorize?: false, load: :homebrew_project) do
      card.origin == :custom and card.homebrew_project.creator_id == actor.id
    else
      _missing_or_not_found -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
