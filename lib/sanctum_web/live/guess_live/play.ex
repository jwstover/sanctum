defmodule SanctumWeb.GuessLive.Play do
  @moduledoc """
  "Flavor Town" — a flavor-text guessing game inspired by the *Stunned &
  Confused* podcast segment. The player is shown a card's flavor text and tries
  to name it. Each wrong guess reveals the next narrowing hint; once the hints
  run out, the next wrong guess ends the round and reveals the card.

  Session-only: round state lives in socket assigns, nothing is persisted.
  """
  use SanctumWeb, :live_view

  alias Sanctum.Games.CardGuess

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:guess}>
      <.header>
        Flavor Town
        <:subtitle>
          Read the flavor text and name the card. Inspired by the <em>Stunned &amp; Confused</em>
          podcast — every wrong guess earns you a hint that narrows it down.
        </:subtitle>
      </.header>

      <.panel :if={@status == :empty} class="px-6 py-12 text-center">
        <div class="font-bangers text-[30px] tracking-[0.02em] text-primary">No cards to guess</div>
        <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
          No cards with flavor text are loaded yet. Sync the catalog and come back.
        </div>
      </.panel>

      <div :if={@status != :empty} class="mx-auto max-w-[720px]">
        <!-- flavor prompt -->
        <.panel class="px-6 py-8">
          <div class="font-ibm-mono text-[10px] uppercase tracking-[0.25em] text-base-content/45">
            Flavor text
          </div>
          <blockquote class="mt-3 font-barlow text-[20px] italic leading-[1.5] text-base-content/90">
            “{@card.primary_side.flavor}”
          </blockquote>
        </.panel>

        <!-- guess form -->
        <form :if={@status == :playing} phx-submit="guess" class="mt-5 flex gap-2.5">
          <input
            type="text"
            name="guess"
            value=""
            autocomplete="off"
            phx-mounted={JS.focus()}
            placeholder="Name the card…"
            class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 font-barlow text-[15px] text-base-content outline-none focus:border-primary placeholder:text-base-content/40"
          />
          <.button variant="primary" type="submit">Guess</.button>
        </form>

        <div :if={@status == :playing} class="mt-2.5 text-right">
          <button
            type="button"
            phx-click="give-up"
            class="font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/40 hover:text-base-content/70"
          >
            Give up
          </button>
        </div>

        <!-- revealed hints -->
        <div :if={@revealed_count > 0} class="mt-6">
          <div class="font-ibm-mono text-[10px] uppercase tracking-[0.25em] text-base-content/45">
            Hints
          </div>
          <ol class="mt-2.5 flex flex-col gap-2">
            <li
              :for={{hint, i} <- Enum.with_index(Enum.take(@hints, @revealed_count), 1)}
              class="flex gap-3 border-2 border-neutral bg-base-200 px-3.5 py-2.5 shadow-comic-sm"
            >
              <span class="font-anton text-[15px] text-primary">{i}.</span>
              <span class="font-barlow text-[15px] text-base-content/90">{hint.text}</span>
            </li>
          </ol>
          <div
            :if={@status == :playing}
            class="mt-2 font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/40"
          >
            {hints_remaining_label(@hints, @revealed_count)}
          </div>
        </div>

        <!-- missed guesses -->
        <div
          :if={@guesses != []}
          class="mt-4 font-barlow text-[13px] text-base-content/50"
        >
          Missed guesses: {Enum.join(@guesses, ", ")}
        </div>

        <!-- result + reveal -->
        <.panel :if={@status in [:won, :lost]} class="mt-6 px-6 py-6 text-center">
          <div class={[
            "font-bangers text-[34px] tracking-[0.02em]",
            (@status == :won && "text-success") || "text-error"
          ]}>
            {(@status == :won && "You got it!") || "Out of guesses!"}
          </div>
          <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
            {(@status == :won && win_label(@revealed_count)) || "The answer was:"}
          </div>

          <div class="mt-5 flex flex-col items-center gap-3">
            <div class="h-[280px] w-[200px] border-2 border-neutral shadow-comic">
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

          <.button variant="primary" phx-click="new-game" class="mt-6">Play again</.button>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Flavor Town") |> start_round()}
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

  defp start_round(socket) do
    case CardGuess.random_guessable_card() do
      nil ->
        socket
        |> assign(:card, nil)
        |> assign(:hints, [])
        |> assign(:revealed_count, 0)
        |> assign(:guesses, [])
        |> assign(:status, :empty)

      card ->
        socket
        |> assign(:card, card)
        |> assign(:hints, CardGuess.build_hints(card))
        |> assign(:revealed_count, 0)
        |> assign(:guesses, [])
        |> assign(:status, :playing)
    end
  end

  defp hints_remaining_label(hints, revealed) do
    case length(hints) - revealed do
      0 -> "No more hints — the next wrong guess ends the round."
      1 -> "1 hint remaining."
      n -> "#{n} hints remaining."
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
