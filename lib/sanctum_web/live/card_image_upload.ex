defmodule SanctumWeb.CardImageUpload do
  @moduledoc """
  Shared bits of the admin card-image replacement flow, used by both the admin
  card page and the public card detail page.
  """

  @doc "Options for `allow_upload/3` on a card-image upload."
  def upload_opts do
    [accept: ~w(.png .jpg .jpeg .tif .tiff), max_entries: 1, max_file_size: 50_000_000]
  end

  @doc "Human-readable message for a LiveView upload error."
  def error_message(:too_large), do: "File is too large (max 50 MB)."
  def error_message(:not_accepted), do: "Unsupported file type (use PNG, JPG, or TIFF)."
  def error_message(:too_many_files), do: "Only one file at a time."
  def error_message(_other), do: "Invalid file."

  @doc "Persists `url` as the side's `image_url` (policy-checked against `actor`)."
  def persist_image_url(side_id, url, actor) do
    Sanctum.Games.CardSide
    |> Ash.get!(side_id, actor: actor)
    |> Ash.Changeset.for_update(:update, %{image_url: url}, actor: actor)
    |> Ash.update!()
  end

  @doc "Appends a cache-busting `?v=` token to `url`."
  def versioned_url(nil, _version), do: nil
  def versioned_url(url, nil), do: url
  def versioned_url(url, version), do: url <> "?v=#{version}"
end
