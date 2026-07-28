defmodule SanctumWeb.ProfileLive.Index do
  @moduledoc """
  The signed-in user's profile: claim (or change) a username, preview the
  avatar, and review the private card collection. Account settings (change
  password, linked sign-in methods) will stack on this page later.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  # The checklist mirrors the Browse page: waves in release order, packs
  # within a wave ranked by product type then release position.
  @type_rank %{core: 0, campaign_expansion: 1, scenario_pack: 2, hero_pack: 3, promo: 4}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:profile}>
      <div class="mx-auto max-w-xl">
        <h1 class="font-anton text-3xl uppercase leading-[0.9] tracking-[0.005em] md:text-4xl">
          Profile
        </h1>

        <.panel class="mt-6 p-5">
          <div class="flex items-center gap-4 border-b-2 border-neutral pb-5">
            <.avatar
              name={display_name(@current_user)}
              url={@current_user.avatar_url}
              seed={display_name(@current_user)}
              size="lg"
            />
            <div class="min-w-0">
              <div class="truncate font-bangers text-2xl leading-none tracking-wide text-primary">
                {display_name(@current_user)}
              </div>
              <div class="mt-1.5 truncate font-ibm-mono text-xs text-base-content/50">
                {@current_user.email}
              </div>
            </div>
          </div>

          <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save" class="mt-5">
            <.input
              field={@form[:username]}
              type="text"
              label="Username"
              autocomplete="username"
              placeholder="e.g. web_head"
            />
            <p class="mt-2 font-barlow-condensed text-sm text-base-content/50">
              3–20 characters: letters, numbers, and underscores. Shown on your decks.
            </p>
            <.button variant="primary" type="submit" class="mt-4">
              Save username
            </.button>
          </.form>
        </.panel>

        <!-- BYOK: the user's own Anthropic key powers "Fill from image" on custom
             cards. Stored encrypted; Sanctum never charges for extraction. The
             plaintext key is never read back here — only the masked hint. -->
        <.panel class="mt-6 p-5">
          <div class="flex items-baseline justify-between border-b-2 border-neutral pb-3">
            <h2 class="font-anton text-xl uppercase tracking-[0.03em]">AI Card Extraction</h2>
            <span :if={@anthropic_key} class="font-ibm-mono text-xs text-success">Connected</span>
          </div>

          <p class="mt-3 font-barlow-condensed text-sm text-base-content/60">
            Bring your own Anthropic API key to auto-fill custom card fields from their
            art. You're billed by Anthropic directly — Sanctum stores your key encrypted
            and never charges for extraction.
          </p>

          <div
            :if={@anthropic_key}
            class="mt-4 flex items-center justify-between gap-3 border-2 border-neutral bg-base-300 px-3 py-2.5"
          >
            <div class="min-w-0">
              <div class="font-ibm-mono text-sm">sk-…{@anthropic_key.key_hint}</div>
              <div
                :if={@anthropic_key.last_validated_at}
                class="mt-0.5 font-ibm-mono text-xs text-base-content/45"
              >
                Validated {Calendar.strftime(@anthropic_key.last_validated_at, "%Y-%m-%d")}
              </div>
            </div>
            <button
              type="button"
              phx-click={open_confirm("confirm-remove-api-key")}
              class="cursor-pointer font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-base-content/60 hover:text-error"
            >
              Remove
            </button>
          </div>

          <.confirm_dialog
            id="confirm-remove-api-key"
            message="Remove your Anthropic API key?"
            confirm_label="Remove"
            phx-click="remove_api_key"
          />

          <.form for={@api_key_form} id="api-key-form" phx-submit="save_api_key" class="mt-4">
            <.input
              field={@api_key_form[:key]}
              type="password"
              label={(@anthropic_key && "Replace key") || "Anthropic API key"}
              placeholder="sk-ant-…"
              autocomplete="off"
            />
            <.button variant="primary" type="submit" class="mt-4" disabled={@validating_key}>
              {if @validating_key, do: "Validating…", else: "Validate & save"}
            </.button>
          </.form>
        </.panel>

        <!-- collection: private to this user (policy-scoped reads). Every
             product in the catalog with a checkbox — the one-place manager. -->
        <.panel class="mt-6 p-5">
          <div class="flex items-baseline justify-between border-b-2 border-neutral pb-3">
            <h2 class="font-anton text-xl uppercase tracking-[0.03em]">Collection</h2>
            <span class="font-ibm-mono text-xs text-base-content/45">
              {@owned_card_count} cards owned
            </span>
          </div>

          <div :for={group <- @collection_groups} class="mt-4">
            <div class="mb-1.5 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/45">
              {group.label} · {group.owned_count} / {length(group.packs)}
            </div>
            <div class="divide-y divide-neutral/50">
              <label
                :for={pack <- group.packs}
                class="flex cursor-pointer items-center gap-2.5 py-1.5"
              >
                <input
                  type="checkbox"
                  checked={MapSet.member?(@owned_pack_ids, pack.id)}
                  phx-click="toggle_pack"
                  phx-value-id={pack.id}
                  class="checkbox checkbox-sm"
                />
                <span class={[
                  "min-w-0 flex-1 truncate font-barlow-condensed text-base font-semibold",
                  !MapSet.member?(@owned_pack_ids, pack.id) && "text-base-content/60"
                ]}>
                  {pack.name || pack.code}
                </span>
                <span :if={pack.released_on} class="font-ibm-mono text-xs text-base-content/40">
                  {pack.released_on.year}
                </span>
                <.link
                  navigate={~p"/browse/#{pack.code}"}
                  title="View contents"
                  class="p-1 text-base-content/40 hover:text-primary"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
                </.link>
              </label>
            </div>
          </div>

          <p
            :if={@override_counts != %{}}
            class="mt-4 font-barlow-condensed text-sm text-base-content/50"
          >
            <span :if={@override_counts[:owned]}>
              Plus {@override_counts[:owned]} individually added {(@override_counts[:owned] == 1 &&
                                                                     "card") || "cards"}.
            </span>
            <span :if={@override_counts[:excluded]}>
              {@override_counts[:excluded]} marked missing from owned packs.
            </span>
          </p>

          <.link
            navigate={~p"/browse"}
            class="mt-4 inline-flex items-center gap-1 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-base-content/60 hover:text-primary"
          >
            Fine-tune individual cards in Browse <.icon name="hero-arrow-right" class="size-3.5" />
          </.link>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:collection_groups, [])
      |> assign(:owned_pack_ids, MapSet.new())
      |> assign(:override_counts, %{})
      |> assign(:owned_card_count, 0)
      |> assign(:anthropic_key, nil)
      |> assign(:validating_key, false)
      |> reset_api_key_form()

    socket =
      if connected?(socket),
        do: socket |> assign_collection() |> assign_api_key(),
        else: socket

    {:ok, assign_form(socket)}
  end

  @impl true
  def handle_event("validate", %{"profile" => params}, socket) do
    {:noreply,
     assign(socket, :form, to_form(AshPhoenix.Form.validate(socket.assigns.form.source, params)))}
  end

  def handle_event("toggle_pack", %{"id" => pack_id}, socket) do
    user = socket.assigns.current_user

    if MapSet.member?(socket.assigns.owned_pack_ids, pack_id),
      do: Sanctum.Collections.remove_pack(pack_id, user),
      else: Sanctum.Collections.add_pack!(pack_id, actor: user)

    {:noreply, assign_collection(socket)}
  end

  # BYOK: validate the pasted key against Anthropic (token-free) before storing
  # it encrypted. Runs async so the network round-trip doesn't block the LV.
  def handle_event("save_api_key", %{"api_key" => %{"key" => key}}, socket) do
    key = String.trim(key)
    user = socket.assigns.current_user

    cond do
      socket.assigns.validating_key ->
        {:noreply, socket}

      key == "" ->
        {:noreply, put_flash(socket, :error, "Enter your Anthropic API key.")}

      true ->
        {:noreply,
         socket
         |> assign(:validating_key, true)
         |> start_async(:save_api_key, fn -> validate_and_store(user, key) end)}
    end
  end

  def handle_event("remove_api_key", _params, socket) do
    case socket.assigns.anthropic_key do
      nil ->
        {:noreply, socket}

      row ->
        Sanctum.Accounts.destroy_api_key(row, actor: socket.assigns.current_user)
        {:noreply, socket |> assign_api_key() |> put_flash(:info, "Anthropic key removed.")}
    end
  end

  def handle_event("save", %{"profile" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign_form()
         |> put_flash(:info, "Username saved.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_async(:save_api_key, {:ok, result}, socket) do
    socket = assign(socket, :validating_key, false)

    case result do
      :ok ->
        {:noreply,
         socket
         |> assign_api_key()
         |> reset_api_key_form()
         |> put_flash(:info, "Anthropic key validated and saved.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, key_error_message(reason))}
    end
  end

  def handle_async(:save_api_key, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:validating_key, false)
     |> put_flash(:error, "Couldn't reach Anthropic — try again.")}
  end

  # Validate then store: only a live key is ever persisted. The plaintext is
  # dropped as soon as the encrypted row is written.
  defp validate_and_store(user, key) do
    case Sanctum.CardVision.validate_key(key) do
      :ok ->
        hint = String.slice(key, -4, 4)

        case Sanctum.Accounts.upsert_api_key(
               %{provider: :anthropic, key: key, key_hint: hint},
               actor: user
             ) do
          {:ok, _row} -> :ok
          {:error, _} -> {:error, :store_failed}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp key_error_message(:invalid),
    do: "Anthropic rejected that key. Check it and try again."

  defp key_error_message(:rate_limited),
    do: "Anthropic rate-limited the check. Try again shortly."

  defp key_error_message(:store_failed),
    do: "The key checked out but couldn't be saved. Try again."

  defp key_error_message({:api_error, status}),
    do: "Anthropic returned an error (#{status}). Try again."

  defp key_error_message(_other), do: "Couldn't reach Anthropic — try again."

  defp assign_api_key(socket) do
    key =
      case Sanctum.Accounts.api_key_for_provider(:anthropic, actor: socket.assigns.current_user) do
        {:ok, row} -> row
        _ -> nil
      end

    assign(socket, :anthropic_key, key)
  end

  defp reset_api_key_form(socket) do
    assign(socket, :api_key_form, to_form(%{"key" => ""}, as: "api_key"))
  end

  defp assign_form(socket) do
    user = socket.assigns.current_user

    form =
      AshPhoenix.Form.for_update(user, :update_profile,
        as: "profile",
        actor: user
      )

    assign(socket, :form, to_form(form))
  end

  defp display_name(%{username: username}) when not is_nil(username), do: "@#{username}"
  defp display_name(%{email: email}), do: to_string(email)

  # The full catalog as a checklist: every pack grouped by release wave (the
  # Browse page's organization) with the user's owned set, plus per-card
  # override counts and the effective owned-card total.
  defp assign_collection(socket) do
    user = socket.assigns.current_user
    owned_pack_ids = Sanctum.Collections.owned_pack_ids(user)

    by_wave =
      Sanctum.Catalog.list_packs!(load: [:wave])
      |> Enum.group_by(& &1.wave)

    groups =
      by_wave
      |> Enum.sort_by(fn
        # Wave-less packs (e.g. standalone modular sets) sort last.
        {nil, _packs} -> 1_000_000
        {wave, _packs} -> wave.number
      end)
      |> Enum.map(fn {wave, packs} ->
        %{
          label: wave_label(wave, packs),
          packs: sort_packs(packs),
          owned_count: Enum.count(packs, &MapSet.member?(owned_pack_ids, &1.id))
        }
      end)

    override_counts =
      [actor: user]
      |> Sanctum.Collections.list_card_overrides!()
      |> Enum.frequencies_by(& &1.status)

    # Counted via a select-id read: Ash.count/2 does not resolve the ^actor
    # template inside the :owned calc's filter (it always counts zero), while
    # the read pipeline does.
    owned_card_count =
      Sanctum.Games.Card
      |> Ash.Query.filter(owned == true)
      |> Ash.Query.select([:id])
      |> Ash.read!(actor: user)
      |> length()

    socket
    |> assign(:collection_groups, groups)
    |> assign(:owned_pack_ids, owned_pack_ids)
    |> assign(:override_counts, override_counts)
    |> assign(:owned_card_count, owned_card_count)
  end

  # "Wave 2 · The Rise of Red Skull" — the campaign expansion (if any) names
  # the wave, matching the Browse page's headings.
  defp wave_label(nil, _packs), do: "Other"

  defp wave_label(wave, packs) do
    case Enum.find(packs, &(&1.product_type == :campaign_expansion)) do
      %{name: name} when is_binary(name) -> "#{wave.name} · #{name}"
      _ -> wave.name
    end
  end

  # Browse-page tile order: product-type rank, then release position.
  defp sort_packs(packs) do
    Enum.sort_by(packs, &{Map.get(@type_rank, &1.product_type, 9), &1.position || 9999})
  end
end
