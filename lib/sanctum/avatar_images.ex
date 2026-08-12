defmodule Sanctum.AvatarImages do
  @moduledoc """
  Stores user-uploaded profile pictures in the public bucket under
  content-addressed keys: `avatars/<sha256-of-stored-bytes><ext>`.

  Same shape as `Sanctum.HomebrewImages` — content addressing gives dedupe and
  immutability, so changing your picture mints a new URL rather than mutating
  an object that other pages may already be caching. Objects are never deleted:
  a hash can be shared between users, and old deck listings keep rendering.

  Note the bucket is **public**: an avatar URL is world-readable by anyone who
  has it, exactly like card scans. Keys are unguessable (sha256 of the stored
  bytes) but not access-controlled.

  Reuses the `Sanctum.CardImages` plumbing (Req + sigv4 against the public
  Tigris bucket) and `Sanctum.CardImages.Processor` normalization.
  """

  alias Sanctum.CardImages
  alias Sanctum.CardImages.Processor

  @s3_env_vars ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 BUCKET_NAME)
  @prefix "avatars/"

  @doc """
  Normalizes `binary` to a square avatar and uploads it under its
  content-addressed key, skipping the PUT when the object already exists.

  `client_type` is the upload's MIME type; JPEG sources stay JPEG, everything
  else is stored as PNG (the Processor's two output formats).

  Returns `{:ok, public_url}` or `{:error, reason}`.
  """
  def store(binary, client_type) when is_binary(binary) do
    ext = target_ext(client_type)

    with {:ok, normalized} <- Processor.normalize_avatar(binary, ext),
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
    @prefix <> Base.encode16(:crypto.hash(:sha256, normalized), case: :lower) <> ext
  end

  @doc """
  Whether a URL points at an avatar object in our own bucket.

  `:update_avatar` is a self-service action, so the URL it accepts has to be
  one we just minted — without this a user could point `avatar_url` at any
  host on the internet and have every deck listing hotlink it.
  """
  def own_url?(url) when is_binary(url), do: String.starts_with?(url, base() <> @prefix)
  def own_url?(_url), do: false

  @doc """
  Whether uploads can work in this environment — all S3 env vars present.
  Lets the UI degrade to a notice instead of raising mid-consume.
  """
  def configured?, do: Enum.all?(@s3_env_vars, &match?({:ok, _}, System.fetch_env(&1)))

  defp url(key), do: base() <> key
  defp base, do: CardImages.base_url() <> "/"

  defp target_ext("image/jpeg"), do: ".jpg"
  defp target_ext(_client_type), do: ".png"
end
