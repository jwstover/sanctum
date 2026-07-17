defmodule SanctumWeb.Components.Avatar do
  @moduledoc """
  User avatar: renders the image when a URL is present, otherwise an initial
  over a deterministic gradient (stable per seed, same primitive heroes use
  for their fallback palette).
  """
  use Phoenix.Component

  alias SanctumWeb.Components.Card, as: CardComponent

  @sizes %{
    "sm" => "size-[26px] text-sm",
    "md" => "size-[28px] text-sm",
    "lg" => "size-[64px] text-3xl"
  }

  @doc """
  Renders a user avatar.

  ## Examples

      <.avatar name={deck.author} url={deck.author_avatar} />
      <.avatar name={@current_user.username} size="lg" />
  """
  attr :name, :string, default: nil, doc: "display label the initial is derived from"
  attr :url, :string, default: nil, doc: "renders an <img> when present"
  attr :seed, :string, default: nil, doc: "gradient seed; defaults to name"
  attr :size, :string, default: "sm", values: ~w(sm md lg)
  attr :class, :any, default: nil

  def avatar(assigns) do
    {from, to} = CardComponent.fallback_gradient(assigns.seed || assigns.name)

    assigns =
      assigns
      |> assign(:size_classes, Map.fetch!(@sizes, assigns.size))
      |> assign(:gradient, "background:linear-gradient(135deg,#{from},#{to});")

    ~H"""
    <img
      :if={@url}
      src={@url}
      alt={@name}
      referrerpolicy="no-referrer"
      loading="lazy"
      class={[
        "rounded-full border-2 border-neutral object-cover",
        @size_classes,
        @class
      ]}
    />
    <span
      :if={!@url}
      style={@gradient}
      class={[
        "flex items-center justify-center rounded-full border-2 border-neutral",
        "font-bangers text-white",
        @size_classes,
        @class
      ]}
    >
      {initial(@name)}
    </span>
    """
  end

  defp initial(name) when is_binary(name) and name != "",
    do: name |> String.trim_leading("@") |> String.first() |> String.upcase()

  defp initial(_name), do: "?"
end
