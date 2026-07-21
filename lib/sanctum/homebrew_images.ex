defmodule Sanctum.HomebrewImages do
  @moduledoc """
  Stores homebrew card images in the public bucket under content-addressed
  keys: `homebrew/<sha256-of-stored-bytes><ext>`.

  Content addressing gives dedupe (an identical upload maps to the same key)
  and immutability by construction — "replacing" art mints a new hash and
  therefore a new URL, so old games and snapshots keep rendering the original
  object forever. Objects are never deleted here: a hash may be shared across
  cards, projects, and users.

  Reuses the `Sanctum.CardImages` plumbing (Req + sigv4 against the public
  Tigris bucket) and `Sanctum.CardImages.Processor` normalization.
  """

  alias Sanctum.CardImages
  alias Sanctum.CardImages.Processor

  @s3_env_vars ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 BUCKET_NAME)

  @doc """
  Normalizes `binary` (any decodable image) and uploads it under its
  content-addressed key, skipping the PUT when the object already exists.

  `client_type` is the upload's MIME type; JPEG sources stay JPEG, everything
  else is stored as PNG (the Processor's two output formats).

  Returns `{:ok, public_url}` or `{:error, reason}`.
  """
  def store(binary, client_type) when is_binary(binary) do
    ext = target_ext(client_type)

    with {:ok, normalized} <- Processor.normalize(binary, ext),
         key = key_for(normalized, ext),
         :ok <- put_unless_exists(key, normalized) do
      {:ok, url(key)}
    end
  end

  defp put_unless_exists(key, normalized) do
    if CardImages.exists?(key), do: :ok, else: CardImages.put_object(key, normalized)
  end

  @doc "Content-addressed bucket key for already-normalized bytes."
  def key_for(normalized, ext) when is_binary(normalized) do
    "homebrew/" <> Base.encode16(:crypto.hash(:sha256, normalized), case: :lower) <> ext
  end

  @doc """
  Whether uploads can work in this environment — all S3 env vars present.
  Lets the UI degrade to a notice instead of raising mid-consume.
  """
  def configured? do
    Enum.all?(@s3_env_vars, &match?({:ok, _}, System.fetch_env(&1)))
  end

  defp url(key), do: CardImages.base_url() <> "/" <> key

  defp target_ext("image/jpeg"), do: ".jpg"
  defp target_ext(_client_type), do: ".png"
end
