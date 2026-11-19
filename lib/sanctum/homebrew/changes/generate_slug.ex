defmodule Sanctum.Homebrew.Changes.GenerateSlug do
  @moduledoc """
  Derives a `HomebrewSet` slug from its name, unique *within its creator*:
  the first free one of `daredevil`, `daredevil-2`, `daredevil-3`, ... among
  that creator's sets. Another creator's `daredevil` never counts, so
  creator-scoped URLs (`/custom/@creator/daredevil`) make collisions between
  creators impossible and being first to a name earns nothing.

  Options:

    * `only_if_missing?` (default `false`) — leave an existing slug alone.
      `:set_visibility` uses this so legacy sets created before slugs existed
      get one when published, while published URLs never move.

  When regenerating, a set whose current slug already matches its name keeps
  it rather than walking to the next free suffix.

  Runs in `before_action` (after policies and after `SetCreatorFromProject`
  stamps `creator_id`, which is registered first). The sibling lookup is a
  system read (`authorize?: false`) that only feeds the choice; the
  `(creator_id, slug)` identity is the backstop if two writes race.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Ash.Changeset
  alias Sanctum.Homebrew.HomebrewSet

  @max_length 60

  @impl true
  def init(opts), do: {:ok, Keyword.validate!(opts, only_if_missing?: false)}

  @impl true
  def change(changeset, opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      if opts[:only_if_missing?] and present?(Changeset.get_attribute(changeset, :slug)) do
        changeset
      else
        Changeset.force_change_attribute(changeset, :slug, pick_slug(changeset))
      end
    end)
  end

  defp pick_slug(changeset) do
    base = slugify(Changeset.get_attribute(changeset, :name))
    current = Changeset.get_data(changeset, :slug)

    if is_binary(current) and current =~ ~r/\A#{base}(-\d+)?\z/ do
      current
    else
      taken = taken_slugs(changeset)

      Stream.iterate(1, &(&1 + 1))
      |> Stream.map(fn
        1 -> base
        n -> "#{base}-#{n}"
      end)
      |> Enum.find(&(not MapSet.member?(taken, &1)))
    end
  end

  # Slugs of this creator's *other* sets. A creator has a handful of sets, so
  # reading them all is cheaper to reason about than a prefix query.
  defp taken_slugs(changeset) do
    creator_id = Changeset.get_attribute(changeset, :creator_id)

    query =
      HomebrewSet
      |> Ash.Query.filter(creator_id == ^creator_id and not is_nil(slug))
      |> Ash.Query.select([:slug])

    query =
      case Changeset.get_data(changeset, :id) do
        nil -> query
        own_id -> Ash.Query.filter(query, id != ^own_id)
      end

    query |> Ash.read!(authorize?: false) |> MapSet.new(& &1.slug)
  end

  @doc """
  URL slug for a set name: ASCII-folded, lowercased, hyphen-separated, capped
  at #{@max_length} characters. Names with nothing slug-able (`"!!!"`) fall
  back to `"set"` (then `set-2`, ...).
  """
  @spec slugify(String.t() | nil) :: String.t()
  def slugify(name) do
    slug =
      (name || "")
      |> String.normalize(:nfd)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, @max_length)
      |> String.trim("-")

    if slug == "", do: "set", else: slug
  end

  defp present?(value), do: is_binary(value) and value != ""
end
