defmodule SanctumWeb.ProfileLive.Index do
  @moduledoc """
  The signed-in user's profile: claim (or change) a username, preview the
  avatar, and review the private card collection. Account settings (change
  password, linked sign-in methods) will stack on this page later.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  # Collection products group by type in release-shelf order.
  @type_order [
    {:core, "Core Set"},
    {:campaign_expansion, "Campaign Expansions"},
    {:scenario_pack, "Scenario Packs"},
    {:hero_pack, "Hero Packs"},
    {:promo, "Promos"},
    {nil, "Other"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:profile}>
      <div class="mx-auto max-w-xl">
        <h1 class="font-anton text-3xl uppercase leading-[0.9] tracking-[0.005em] md:text-[42px]">
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
              <div class="truncate font-bangers text-[26px] leading-none tracking-wide text-primary">
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
            <p class="mt-2 font-barlow-condensed text-[13px] text-base-content/50">
              3–20 characters: letters, numbers, and underscores. Shown on your decks.
            </p>
            <.button variant="primary" type="submit" class="mt-4">
              Save username
            </.button>
          </.form>
        </.panel>

        <!-- collection: private to this user (policy-scoped reads). Every
             product in the catalog with a checkbox — the one-place manager. -->
        <.panel class="mt-6 p-5">
          <div class="flex items-baseline justify-between border-b-2 border-neutral pb-3">
            <h2 class="font-anton text-[20px] uppercase tracking-[0.03em]">Collection</h2>
            <span class="font-ibm-mono text-[11px] text-base-content/45">
              {@owned_card_count} cards owned
            </span>
          </div>

          <div :for={group <- @collection_groups} class="mt-4">
            <div class="mb-1.5 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/45">
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
                  "min-w-0 flex-1 truncate font-barlow-condensed text-[15px] font-semibold",
                  !MapSet.member?(@owned_pack_ids, pack.id) && "text-base-content/60"
                ]}>
                  {pack.name || pack.code}
                </span>
                <span :if={pack.released_on} class="font-ibm-mono text-[11px] text-base-content/40">
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
            class="mt-4 font-barlow-condensed text-[13px] text-base-content/50"
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
            class="mt-4 inline-flex items-center gap-1 font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.06em] text-base-content/60 hover:text-primary"
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

    socket = if connected?(socket), do: assign_collection(socket), else: socket

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

  # The full catalog as a checklist: every pack grouped by product type with
  # the user's owned set, plus per-card override counts and the effective
  # owned-card total.
  defp assign_collection(socket) do
    user = socket.assigns.current_user
    owned_pack_ids = Sanctum.Collections.owned_pack_ids(user)

    by_type =
      Sanctum.Catalog.list_packs!()
      |> Enum.group_by(& &1.product_type)

    groups =
      for {type, label} <- @type_order,
          type_packs = Map.get(by_type, type, []),
          type_packs != [] do
        %{
          label: label,
          packs: Enum.sort_by(type_packs, &(&1.position || 9999)),
          owned_count: Enum.count(type_packs, &MapSet.member?(owned_pack_ids, &1.id))
        }
      end

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
end
