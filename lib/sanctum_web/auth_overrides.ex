defmodule SanctumWeb.AuthOverrides do
  @moduledoc """
  UI overrides mapping the AshAuthentication.Phoenix pages (sign-in, register,
  reset, confirm, magic link, sign-out) onto the comic-dossier design system:
  halftone canvas, hard-black-bordered cardstock panel, Bangers wordmark,
  Anton headings, and the gold offset-shadow CTA.

  Reference: https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html
  """

  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{
    Components,
    ConfirmLive,
    MagicSignInLive,
    ResetLive,
    SignInLive,
    SignOutLive
  }

  # Full-page halftone canvas behind the centered auth panel.
  @page_class "min-h-screen grid place-items-center bg-base-100 bg-halftone px-4 py-12"

  # The "printed cardstock" panel every auth surface sits on.
  @panel_class "w-full max-w-sm border-2 border-neutral bg-base-200 shadow-comic px-8 py-10"

  # Comic button primitives (mirrors CoreComponents.button/1 variants).
  @button_base "w-full inline-flex min-h-[44px] items-center justify-center gap-2 cursor-pointer " <>
                 "px-4 py-2.5 font-barlow-condensed font-extrabold uppercase tracking-[0.08em] text-sm " <>
                 "transition-all active:translate-x-px active:translate-y-px disabled:opacity-40 disabled:pointer-events-none"
  @button_primary @button_base <>
                    " bg-primary text-primary-content border-2 border-transparent shadow-comic-sm hover:shadow-comic"
  @button_ghost @button_base <>
                  " bg-base-300 text-base-content border-2 border-neutral shadow-comic-sm hover:text-white"

  # Form primitives (mirrors CoreComponents.input/1).
  @heading_class "font-anton text-2xl uppercase tracking-[0.03em] leading-none text-base-content mt-2 mb-5"
  @field_label_class "block font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/60 mb-1.5"
  @input_base "appearance-none block w-full bg-black border-[2.5px] text-base-content font-barlow " <>
                "px-3.5 py-2.5 text-sm outline-none placeholder:text-base-content/40"
  @input_class @input_base <> " border-line focus:border-primary"
  @input_error_class @input_base <> " border-error focus:border-error"

  # Public accessors so SanctumWeb.AuthSignInLive's hand-rolled register page
  # (which bypasses the override system) stays pixel-identical to the stock
  # auth surfaces styled above.
  def page_class, do: @page_class
  def panel_class, do: @panel_class
  def heading_class, do: @heading_class
  def field_label_class, do: @field_label_class
  def input_class, do: @input_class
  def input_error_class, do: @input_error_class
  def button_primary, do: @button_primary
  def button_ghost, do: @button_ghost

  override SignInLive do
    set :root_class, @page_class
  end

  override SignOutLive do
    set :root_class, @page_class
  end

  override ResetLive do
    set :root_class, @page_class
  end

  override ConfirmLive do
    set :root_class, @page_class
  end

  override MagicSignInLive do
    set :root_class, @page_class
  end

  override Components.SignIn do
    set :root_class, @panel_class
    set :strategy_class, "w-full"
    set :authentication_error_container_class, "text-center mt-2"
    set :authentication_error_text_class, "font-barlow text-sm text-error"
  end

  override Components.SignOut do
    set :root_class, @panel_class
    set :h2_class, @heading_class
    set :info_text_class, "font-barlow text-sm text-base-content/70 mb-5"
    set :button_class, @button_primary
  end

  override Components.Reset do
    set :root_class, @panel_class
    set :strategy_class, "w-full"
  end

  override Components.Reset.Form do
    set :label_class, @heading_class
  end

  override Components.Confirm do
    set :root_class, @panel_class
    set :strategy_class, "w-full"
  end

  override Components.Confirm.Input do
    set :submit_class, @button_primary <> " mt-4"
  end

  # Wordmark in place of the Ash Framework banner.
  override Components.Banner do
    set :root_class, "w-full pb-6 mb-6 border-b-2 border-neutral text-center"
    set :image_url, nil
    set :dark_image_url, nil
    set :href_url, "/"
    set :text, "SANCTUM"
    set :text_class, "font-bangers text-4xl leading-none tracking-wide text-primary"
  end

  override Components.HorizontalRule do
    set :root_class, "relative my-5"
    set :hr_inner_class, "w-full border-t-2 border-neutral"

    set :text_inner_class,
        "px-3 bg-base-200 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50"
  end

  override Components.MagicLink do
    set :root_class, "mt-2 mb-2"
    set :label_class, @heading_class
  end

  override Components.MagicLink.Input do
    set :submit_class, @button_primary <> " mt-4"
    set :remember_me_class, "flex items-center gap-2 mt-3"
    set :checkbox_class, "checkbox checkbox-sm"

    set :checkbox_label_class,
        "font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-base-content/70"
  end

  override Components.Password do
    set :root_class, "mt-2 mb-2"
    set :interstitial_class, "flex flex-row justify-between content-between mt-3"

    set :toggler_class,
        "flex-none px-2 first:pl-0 last:pr-0 font-barlow-condensed text-sm font-bold " <>
          "uppercase tracking-[0.06em] text-primary hover:underline underline-offset-4"
  end

  override Components.Password.SignInForm do
    set :label_class, @heading_class
  end

  override Components.Password.RegisterForm do
    set :label_class, @heading_class
  end

  override Components.Password.ResetForm do
    set :label_class, @heading_class
  end

  override Components.Password.Input do
    set :field_class, "mt-3"
    set :label_class, @field_label_class
    set :input_class, @input_class
    set :input_class_with_error, @input_error_class
    set :submit_class, @button_primary <> " mt-5"
    set :error_ul, "font-barlow text-sm text-error mt-2 space-y-1"
    set :remember_me_class, "flex items-center gap-2 mt-3"
    set :checkbox_class, "checkbox checkbox-sm"

    set :checkbox_label_class,
        "font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-base-content/70"
  end

  override Components.OAuth2 do
    set :root_class, "w-full mt-2 mb-2"
    set :link_class, @button_ghost
    set :icon_class, "size-5 shrink-0"
    # The library has no built-in Discord icon SVG (it falls back to a generic
    # padlock), so the stock sign-in page pulls it from a static asset.
    set :icon_src, %{discord: "/images/discord-mark.svg"}
  end

  override Components.Flash do
    set :message_class_info,
        "fixed top-3 right-3 w-80 sm:w-96 z-50 border-2 border-neutral bg-base-200 shadow-comic " <>
          "p-3 font-barlow text-sm text-base-content border-l-[6px] border-l-info"

    set :message_class_error,
        "fixed top-3 right-3 w-80 sm:w-96 z-50 border-2 border-neutral bg-base-200 shadow-comic " <>
          "p-3 font-barlow text-sm text-base-content border-l-[6px] border-l-error"
  end
end
