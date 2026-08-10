defmodule Sanctum.CardImages.Processor do
  @moduledoc """
  Normalizes admin-uploaded card images before they land in the bucket.

  Every upload — PNG, JPG, or TIFF — is decoded with libvips (via Vix),
  downscaled to fit within #{1200}×#{1200} px (never upscaled), and re-encoded
  to the format the target object key implies. Converting to the key's
  extension keeps the stored bytes, the key, and the served content type in
  agreement, so `image_url` never has to change when an image is replaced.
  """

  @max_dimension 1200
  @jpeg_quality 90
  @avatar_dimension 512

  @doc """
  Decodes `binary`, caps its long edge at #{@max_dimension} px, and re-encodes
  it as the format `target_ext` implies (`".jpg"`/`".jpeg"` → JPEG, anything
  else → PNG).

  Returns `{:ok, converted_binary}` or `{:error, reason}` when the bytes are
  not a decodable image.
  """
  def normalize(binary, target_ext) when is_binary(binary) do
    with {:ok, image} <- thumbnail(binary) do
      Vix.Vips.Image.write_to_buffer(image, save_suffix(target_ext))
    end
  end

  @doc """
  Like `normalize/2`, but produces a square #{@avatar_dimension}×#{@avatar_dimension}
  image for use as a profile picture.

  Avatars render in a small circle, so a "fit inside the box" resize is wrong —
  a wide photo would letterbox. This crops to square instead, using libvips'
  attention strategy to pick the region (it scores skin tones and edges, so
  faces survive the crop rather than being sliced by a naive centre cut).
  """
  def normalize_avatar(binary, target_ext) when is_binary(binary) do
    with {:ok, image} <- avatar_thumbnail(binary) do
      Vix.Vips.Image.write_to_buffer(image, save_suffix(target_ext))
    end
  end

  # `thumbnail_buffer` decodes + downscales in one streaming pass and applies
  # EXIF orientation. `:VIPS_SIZE_DOWN` fits within the box without upscaling.
  defp thumbnail(binary) do
    Vix.Vips.Operation.thumbnail_buffer(binary, @max_dimension,
      height: @max_dimension,
      size: :VIPS_SIZE_DOWN
    )
  end

  # No `size:` option here — avatars are upscaled to fill the square when the
  # source is small, so every stored avatar has identical dimensions.
  defp avatar_thumbnail(binary) do
    Vix.Vips.Operation.thumbnail_buffer(binary, @avatar_dimension,
      height: @avatar_dimension,
      crop: :VIPS_INTERESTING_ATTENTION
    )
  end

  defp save_suffix(ext) when ext in [".jpg", ".jpeg"], do: ".jpg[Q=#{@jpeg_quality}]"
  defp save_suffix(_ext), do: ".png"
end
