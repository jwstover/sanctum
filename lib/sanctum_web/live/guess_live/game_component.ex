defmodule SanctumWeb.GuessLive.GameComponent do
  @moduledoc """
  One playable Flavor Town round, extracted from `GuessLive.Play` so the full
  page and the homepage embed share the implementation.

  Modes:

  - `:full` (`/flavor-town`) — a random guessable card per round, the sticky
    mobile guess bar, and "Play again" restarting in place.
  - `:embedded` (homepage) — the deterministic daily teaser card
    (`CardOfTheDay.flavor_teaser/0`) as the one round, an inline guess bar,
    and a "Play more" link into `/flavor-town` once the round ends.

  Session-only: round state lives in component assigns, nothing is persisted.
  """
  use SanctumWeb, :live_component

  alias Sanctum.Games.CardGuess
  alias Sanctum.Games.CardOfTheDay

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.panel :if={@status == :empty} class="px-6 py-12 text-center">
        <div class="font-bangers text-[30px] tracking-[0.02em] text-primary">No cards to guess</div>
        <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
          No cards with flavor text are loaded yet. Sync the catalog and come back.
        </div>
      </.panel>

      <.panel :if={@status == :loading} class="px-5 py-9 sm:px-6 sm:py-8">
        <div class="animate-pulse space-y-4">
          <div class="h-2.5 w-24 bg-base-300"></div>
          <div class="mt-3 h-6 w-full bg-base-300"></div>
          <div class="h-6 w-5/6 bg-base-300"></div>
          <div class="h-6 w-2/3 bg-base-300"></div>
        </div>
      </.panel>

      <div
        :if={@status not in [:empty, :loading]}
        class={[
          @mode == :full && "mx-auto max-w-[720px]",
          @mode == :full && @status == :playing && "pb-36 sm:pb-0"
        ]}
      >
        <!-- flavor prompt — the hero of the round -->
        <.panel class="relative overflow-hidden px-5 py-9 sm:px-6 sm:py-8">
          <div
            class="pointer-events-none absolute -left-1 -top-5 font-bangers text-[90px] leading-none text-primary/15 select-none sm:text-[70px]"
            aria-hidden="true"
          >
            “
          </div>
          <div class="relative font-ibm-mono text-[10px] uppercase tracking-[0.25em] text-base-content/45">
            Flavor text
          </div>
          <blockquote class="relative mt-3 font-barlow text-[23px] italic leading-[1.42] text-base-content/90 [text-wrap:balance] sm:text-[20px] sm:leading-[1.5]">
            {@card.primary_side.flavor}
          </blockquote>
        </.panel>

        <!-- hint progress HUD (persistent during play) -->
        <div :if={@status == :playing and @hints != []} class="mt-4 flex items-center gap-2.5">
          <span class="font-ibm-mono text-[10px] uppercase tracking-[0.25em] text-base-content/45">
            Hints
          </span>
          <div class="flex items-center gap-1.5">
            <span
              :for={n <- 1..length(@hints)}
              class={[
                "size-[11px] border-2 border-neutral",
                (n <= @revealed_count && "bg-primary") || "bg-base-300"
              ]}
            />
          </div>
          <span class={[
            "ml-auto font-ibm-mono text-[10px] uppercase tracking-[0.15em]",
            (@revealed_count >= length(@hints) && "text-error") || "text-base-content/45"
          ]}>
            {hint_hud_label(@hints, @revealed_count)}
          </span>
        </div>

        <!-- revealed hints -->
        <div :if={@revealed_count > 0} class="mt-5">
          <ol class="flex flex-col gap-2">
            <li
              :for={{hint, i} <- Enum.with_index(Enum.take(@hints, @revealed_count), 1)}
              class="flex gap-3 border-2 border-neutral bg-base-200 px-3.5 py-3 shadow-comic-sm"
            >
              <span class="font-anton text-[15px] text-primary">{i}.</span>
              <span class="font-barlow text-[15px] leading-[1.4] text-base-content/90">
                {hint.text}
              </span>
            </li>
          </ol>
        </div>

        <!-- missed guesses -->
        <div :if={@guesses != []} class="mt-4 font-barlow text-[13px] text-base-content/50">
          Missed guesses: {Enum.join(@guesses, ", ")}
        </div>

        <!-- guess bar: sticky to the bottom on mobile in full mode, inline
             otherwise (an embedded game must not overlay the host page) -->
        <div
          :if={@status == :playing}
          class={
            (@mode == :full &&
               "fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-3 backdrop-blur sm:static sm:mt-5 sm:border-0 sm:bg-transparent sm:px-0 sm:py-0 sm:backdrop-blur-none") ||
              "mt-5"
          }
        >
          <div class={@mode == :full && "mx-auto max-w-[720px]"}>
            <form phx-submit="guess" phx-target={@myself} class="flex gap-2.5">
              <input
                type="text"
                name="guess"
                value=""
                autocomplete="off"
                phx-mounted={@mode == :full && JS.focus()}
                placeholder="Name the card…"
                class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 font-barlow text-base text-base-content outline-none focus:border-primary placeholder:text-base-content/40 sm:text-[15px]"
              />
              <.button variant="primary" type="submit">Guess</.button>
            </form>
            <div class="mt-2 text-center sm:mt-2.5 sm:text-right">
              <button
                type="button"
                phx-click="give-up"
                phx-target={@myself}
                class="inline-flex min-h-[44px] items-center font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/40 hover:text-base-content/70 sm:min-h-0"
              >
                Give up
              </button>
            </div>
          </div>
        </div>

        <!-- result + reveal -->
        <.panel :if={@status in [:won, :lost]} class="mt-6 px-5 py-7 text-center sm:px-6 sm:py-6">
          <div class={[
            "font-bangers text-[38px] tracking-[0.02em] sm:text-[34px]",
            (@status == :won && "text-success") || "text-error"
          ]}>
            {(@status == :won && "You got it!") || "Out of guesses!"}
          </div>
          <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
            {(@status == :won && win_label(@revealed_count)) || "The answer was:"}
          </div>

          <div class="mt-5 flex flex-col items-center gap-3">
            <div class={[
              "border-2 border-neutral shadow-comic",
              (landscape_type?(@card.primary_side.type) && "h-[200px] w-[280px]") ||
                "h-[280px] w-[200px]"
            ]}>
              <.mc_card
                name={@card.primary_side.name}
                aspect={reveal_aspect(@card)}
                type={@card.primary_side.type}
                cost={@card.primary_side.cost}
                image_url={@card.primary_side.image_url}
                size="lg"
                show_cost={false}
              />
            </div>
            <div>
              <div class="font-anton text-[26px] uppercase leading-[0.95]">
                {@card.primary_side.name}
              </div>
              <div
                :if={@card.primary_side.subname not in [nil, ""]}
                class="font-barlow italic text-[14px] text-base-content/60"
              >
                {@card.primary_side.subname}
              </div>
            </div>
          </div>

          <.button
            :if={@mode == :full}
            variant="primary"
            phx-click="new-game"
            phx-target={@myself}
            class="mt-6 w-full sm:w-auto"
          >
            Play again
          </.button>
          <.button
            :if={@mode == :embedded}
            variant="primary"
            navigate={~p"/flavor-town"}
            class="mt-6 w-full sm:w-auto"
          >
            Play more
          </.button>
        </.panel>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:mode, Map.get(assigns, :mode, :full))
      |> assign_new(:card, fn -> nil end)
      |> assign_new(:hints, fn -> [] end)
      |> assign_new(:revealed_count, fn -> 0 end)
      |> assign_new(:guesses, fn -> [] end)
      # :loading until the async pick lands — drives the loading skeleton.
      |> assign_new(:status, fn -> :loading end)
      |> assign_new(:started?, fn -> false end)

    # Skip the card pick on the static render (same as the old page mount);
    # update/2 runs again on the connected mount, which kicks it off once.
    socket =
      if connected?(socket) and not socket.assigns.started? do
        socket |> assign(:started?, true) |> start_round()
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_round, {:ok, card}, socket) do
    {:noreply, apply_round(socket, card)}
  end

  def handle_async(:load_round, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :status, :empty)}
  end

  @impl true
  def handle_event("guess", %{"guess" => guess}, socket) do
    trimmed = String.trim(guess)

    cond do
      socket.assigns.status != :playing or trimmed == "" ->
        {:noreply, socket}

      CardGuess.correct?(trimmed, socket.assigns.card) ->
        {:noreply, assign(socket, :status, :won)}

      true ->
        {:noreply, register_miss(socket, trimmed)}
    end
  end

  def handle_event("give-up", _params, socket) do
    {:noreply, assign(socket, :status, :lost)}
  end

  def handle_event("new-game", _params, socket) do
    {:noreply, start_round(socket)}
  end

  # Reveals the next hint on a miss; once every hint is out, the miss loses.
  defp register_miss(socket, guess) do
    %{revealed_count: revealed, hints: hints} = socket.assigns
    socket = update(socket, :guesses, &(&1 ++ [guess]))

    if revealed < length(hints) do
      assign(socket, :revealed_count, revealed + 1)
    else
      assign(socket, :status, :lost)
    end
  end

  # Kick off a round: the pick runs off the socket so the guess UI never
  # blocks on the DB. Embedded rounds use the shared daily card so everyone
  # gets the same homepage puzzle; the full page stays random per round.
  defp start_round(socket) do
    picker =
      case socket.assigns.mode do
        :embedded -> &CardOfTheDay.flavor_teaser/0
        _full -> &CardGuess.random_guessable_card/0
      end

    socket
    |> assign(:status, :loading)
    |> assign(:revealed_count, 0)
    |> assign(:guesses, [])
    |> start_async(:load_round, picker)
  end

  defp apply_round(socket, nil) do
    socket
    |> assign(:card, nil)
    |> assign(:hints, [])
    |> assign(:revealed_count, 0)
    |> assign(:guesses, [])
    |> assign(:status, :empty)
  end

  defp apply_round(socket, card) do
    socket
    |> assign(:card, card)
    |> assign(:hints, CardGuess.build_hints(card))
    |> assign(:revealed_count, 0)
    |> assign(:guesses, [])
    |> assign(:status, :playing)
  end

  # Compact HUD counter shown beside the hint pips during play.
  defp hint_hud_label(hints, revealed) do
    case length(hints) - revealed do
      0 -> "Final guess"
      1 -> "1 left"
      n -> "#{n} left"
    end
  end

  defp win_label(0), do: "Nailed it with no hints!"
  defp win_label(1), do: "Solved after 1 hint."
  defp win_label(n), do: "Solved after #{n} hints."

  # mc_card wants an aspect string; fall back to the ownership pool (and the
  # component itself falls back to "basic" styling for encounter/campaign).
  defp reveal_aspect(%{primary_side: %{aspect: aspect}}) when not is_nil(aspect),
    do: to_string(aspect)

  defp reveal_aspect(%{primary_side: %{ownership: ownership}}) when not is_nil(ownership),
    do: to_string(ownership)

  defp reveal_aspect(_), do: "basic"
end
