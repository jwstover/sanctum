defmodule Sanctum.CardImages.ProcessorTest do
  use ExUnit.Case, async: true

  alias Sanctum.CardImages.Processor

  @png_magic <<0x89, "PNG">>
  @jpeg_magic <<0xFF, 0xD8, 0xFF>>

  # Fixtures are generated with Vix itself so no binary blobs live in the repo.
  defp image_bytes(width, height, suffix) do
    {:ok, image} = Vix.Vips.Operation.black(width, height)
    {:ok, bytes} = Vix.Vips.Image.write_to_buffer(image, suffix)
    bytes
  end

  defp dimensions(bytes) do
    {:ok, image} = Vix.Vips.Image.new_from_buffer(bytes)
    {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}
  end

  describe "normalize/2" do
    test "converts a TIFF to PNG" do
      assert {:ok, converted} = Processor.normalize(image_bytes(400, 560, ".tif"), ".png")
      assert @png_magic <> _ = converted
    end

    test "converts a TIFF to JPEG when the target is .jpg" do
      assert {:ok, converted} = Processor.normalize(image_bytes(400, 560, ".tif"), ".jpg")
      assert @jpeg_magic <> _ = converted
    end

    test "downscales oversized images to fit within 1200px" do
      assert {:ok, converted} = Processor.normalize(image_bytes(4000, 3000, ".tif"), ".png")
      assert {1200, 900} = dimensions(converted)
    end

    test "does not upscale small images" do
      assert {:ok, converted} = Processor.normalize(image_bytes(400, 560, ".png"), ".png")
      assert {400, 560} = dimensions(converted)
    end

    test "caps the long edge for portrait images" do
      assert {:ok, converted} = Processor.normalize(image_bytes(1500, 2100, ".png"), ".png")
      assert {_, 1200} = dimensions(converted)
    end

    test "returns an error for undecodable bytes" do
      assert {:error, _} = Processor.normalize(<<"not an image">>, ".png")
    end
  end

  describe "normalize_avatar/2" do
    test "crops a wide image to a 512px square" do
      assert {:ok, converted} =
               Processor.normalize_avatar(image_bytes(4000, 1000, ".png"), ".png")

      assert {512, 512} = dimensions(converted)
    end

    test "crops a tall image to a 512px square" do
      assert {:ok, converted} = Processor.normalize_avatar(image_bytes(600, 3000, ".png"), ".png")
      assert {512, 512} = dimensions(converted)
    end

    test "upscales a small image so every avatar is the same size" do
      assert {:ok, converted} = Processor.normalize_avatar(image_bytes(64, 64, ".png"), ".png")
      assert {512, 512} = dimensions(converted)
    end

    test "honours the target format" do
      assert {:ok, converted} = Processor.normalize_avatar(image_bytes(800, 800, ".png"), ".jpg")
      assert @jpeg_magic <> _ = converted
    end

    test "returns an error for undecodable bytes" do
      assert {:error, _} = Processor.normalize_avatar(<<"not an image">>, ".png")
    end
  end
end
