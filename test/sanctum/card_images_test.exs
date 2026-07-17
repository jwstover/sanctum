defmodule Sanctum.CardImagesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.CardImages

  describe "object_key/1" do
    test "keys are the imagesrc basename under cards/" do
      assert CardImages.object_key("/bundles/cards/01001a.png") == "cards/01001a.png"
      # main scheme fronts are unsuffixed; extensions vary
      assert CardImages.object_key("/bundles/cards/01097.png") == "cards/01097.png"
      assert CardImages.object_key("/bundles/cards/26002a.jpg") == "cards/26002a.jpg"
    end

    test "absolute URLs keep their basename" do
      assert CardImages.object_key("https://marvelcdb.com/bundles/cards/01001a.png") ==
               "cards/01001a.png"
    end

    test "nil and empty are nil" do
      assert CardImages.object_key(nil) == nil
      assert CardImages.object_key("") == nil
    end
  end

  describe "public_url/1" do
    test "prefixes the configured bucket base URL" do
      assert CardImages.public_url("/bundles/cards/01097b.png") ==
               CardImages.base_url() <> "/cards/01097b.png"
    end

    test "nil and empty are nil" do
      assert CardImages.public_url(nil) == nil
      assert CardImages.public_url("") == nil
    end
  end

  describe "key_from_url/1" do
    test "recovers the object key from a stored bucket URL" do
      url = CardImages.base_url() <> "/cards/12001c.png"
      assert CardImages.key_from_url(url) == "cards/12001c.png"
    end

    test "round-trips with public_url/1" do
      assert "/bundles/cards/01097b.png"
             |> CardImages.public_url()
             |> CardImages.key_from_url() == "cards/01097b.png"
    end

    test "falls back to cards/<basename> for foreign URLs" do
      assert CardImages.key_from_url("https://example.com/whatever/99999a.png") ==
               "cards/99999a.png"
    end

    test "nil and empty are nil" do
      assert CardImages.key_from_url(nil) == nil
      assert CardImages.key_from_url("") == nil
    end
  end
end
