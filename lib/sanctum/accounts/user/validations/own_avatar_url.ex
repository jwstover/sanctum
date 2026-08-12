defmodule Sanctum.Accounts.User.Validations.OwnAvatarUrl do
  @moduledoc """
  Rejects an `avatar_url` that doesn't point at an object under our own
  bucket's `avatars/` prefix.

  `:update_avatar` is self-service and takes its URL from params, so without
  this a user could set their avatar to any URL on the internet — which every
  public deck listing would then hotlink on their behalf.
  """

  use Ash.Resource.Validation

  alias Sanctum.AvatarImages

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :avatar_url) do
      url when is_binary(url) ->
        if AvatarImages.own_url?(url), do: :ok, else: {:error, error()}

      _ ->
        {:error, error()}
    end
  end

  defp error do
    Ash.Error.Changes.InvalidAttribute.exception(
      field: :avatar_url,
      message: "must be an uploaded avatar"
    )
  end
end
