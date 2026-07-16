defmodule Sanctum.CardImages do
  @moduledoc """
  Mirrors MarvelCDB card scans into the public object-storage bucket and builds
  the public URLs the app renders from.

  Rendering never needs credentials — `image_url` on card sides points straight
  at the public bucket. Only `mirror/2` (run from `mix sanctum.sync_cards`)
  needs the S3 env vars: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_ENDPOINT_URL_S3`, and `BUCKET_NAME`.
  """

  @user_agent "sanctum (personal Marvel Champions smart table; one-time mirror)"

  @doc """
  Bucket object key for a MarvelCDB `imagesrc` path.

  Filenames are taken verbatim from `imagesrc` — MarvelCDB's naming doesn't
  follow card codes (`01097.png` is the front of `01097a`; extensions vary
  between `.png` and `.jpg`), so the basename must never be reconstructed.
  """
  def object_key(nil), do: nil
  def object_key(""), do: nil
  def object_key(imagesrc) when is_binary(imagesrc), do: "cards/" <> Path.basename(imagesrc)

  @doc "Public bucket URL for a MarvelCDB `imagesrc` path, or nil."
  def public_url(imagesrc) do
    case object_key(imagesrc) do
      nil -> nil
      key -> base_url() <> "/" <> key
    end
  end

  def base_url, do: Application.fetch_env!(:sanctum, :card_image_base_url)

  @doc """
  Object key for a stored `image_url` (a full public bucket URL), or nil.

  Inverse of `public_url/1`: strips the bucket base URL to recover the key.
  Falls back to `cards/<basename>` for any other absolute path or bare name,
  so an admin replacement always lands under the `cards/` prefix.
  """
  def key_from_url(nil), do: nil
  def key_from_url(""), do: nil

  def key_from_url(url) when is_binary(url) do
    prefix = base_url() <> "/"

    if String.starts_with?(url, prefix) do
      String.replace_prefix(url, prefix, "")
    else
      object_key(url)
    end
  end

  @doc "Whether the object already exists in the bucket (unsigned HEAD on the public URL)."
  def exists?(key) when is_binary(key) do
    case Req.head(base_url() <> "/" <> key, retry: false) do
      {:ok, %Req.Response{status: 200}} -> true
      _ -> false
    end
  end

  @doc """
  Downloads one scan from marvelcdb.com and uploads it to the bucket.

  Skips the download entirely when the object already exists (unless
  `force: true`), which makes interrupted syncs resumable by re-running.

  Returns `{:ok, :uploaded | :skipped | :no_image}` or `{:error, reason}`.
  """
  def mirror(imagesrc, opts \\ []) do
    case object_key(imagesrc) do
      nil ->
        {:ok, :no_image}

      key ->
        if not Keyword.get(opts, :force, false) and exists?(key) do
          {:ok, :skipped}
        else
          download_and_upload(imagesrc, key)
        end
    end
  end

  defp download_and_upload(imagesrc, key) do
    with {:ok, body} <- download(imagesrc),
         :ok <- put_object(key, body) do
      {:ok, :uploaded}
    end
  end

  defp download(imagesrc) do
    source =
      if String.starts_with?(imagesrc, "http"),
        do: imagesrc,
        else: "https://marvelcdb.com" <> imagesrc

    # Unlike the API (where 500 means "not found"), scans are static files —
    # transient errors are worth retrying, and a missing scan is a plain 404.
    source
    |> Req.get([headers: [user_agent: @user_agent], max_retries: 2] ++ req_options())
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:download_failed, status, imagesrc}}
      {:error, exception} -> {:error, {:download_failed, exception, imagesrc}}
    end
  end

  @doc """
  Uploads raw `body` bytes to the bucket at `key`, overwriting any existing
  object. Needs the S3 env vars (see moduledoc). `content_type` defaults to a
  value inferred from the key's extension.

  Returns `:ok` or `{:error, reason}`.
  """
  def put_object(key, body, content_type \\ nil) do
    endpoint = System.fetch_env!("AWS_ENDPOINT_URL_S3")
    bucket = System.fetch_env!("BUCKET_NAME")

    "#{endpoint}/#{bucket}/#{key}"
    |> Req.put(
      body: body,
      headers: [content_type: content_type || content_type(key)],
      aws_sigv4: [
        access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
        service: :s3,
        region: "auto"
      ]
    )
    |> case do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:upload_failed, status, key}}
      {:error, exception} -> {:error, {:upload_failed, exception, key}}
    end
  end

  defp content_type(key) do
    case Path.extname(key) do
      ".png" -> "image/png"
      ext when ext in [".jpg", ".jpeg"] -> "image/jpeg"
      _ -> "application/octet-stream"
    end
  end

  defp req_options, do: Application.get_env(:sanctum, :marvel_cdb_req_options, [])
end
