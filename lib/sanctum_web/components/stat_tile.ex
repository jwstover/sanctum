defmodule SanctumWeb.Components.StatTile do
  @moduledoc """
  The comic-dossier headline stat tile — a big `font-bangers` count over a
  mono label. Shared by the homepage and the public stats page. (The admin
  landing page has its own plainer variant.)
  """

  use Phoenix.Component

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :color, :string, default: "text-primary"

  def stat_tile(assigns) do
    ~H"""
    <div class="border-[3px] border-neutral bg-base-300 px-4 py-3">
      <div class={["font-bangers text-3xl leading-none", @color]}>{format_count(@value)}</div>
      <div class="mt-1 font-ibm-mono text-xs uppercase tracking-[0.15em] text-base-content/55">
        {@label}
      </div>
    </div>
    """
  end

  @doc "51461 → \"51,461\""
  def format_count(n) do
    n
    |> Integer.to_string()
    |> String.replace(~r/(?<=\d)(?=(\d{3})+$)/, ",")
  end
end
