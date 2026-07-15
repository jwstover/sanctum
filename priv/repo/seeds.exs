alias Sanctum.Accounts
alias Sanctum.Games
alias Sanctum.MarvelCdb

# Syncs the product/pack catalog (+ curated wave/product-type overlay), then
# seeds only the core set with marvelcdb-hosted image URLs; run
# `mix sanctum.sync_cards` to load everything and point images at the bucket.
:ok = MarvelCdb.sync_packs()
:ok = MarvelCdb.load_pack("core")

Games.create_scenario!(%{name: "Rhino", set: "rhino", recommended_modular_sets: ["bomb_scare"]})

# Bootstrap admin. Idempotent: the user is normally created on first Google
# sign-in, so find-or-create by email, then set the admin flag. A later Google
# sign-in upserts on email with upsert_fields [], so it won't clear admin.
admin_email = "jwstover@gmail.com"

admin_user =
  case Accounts.get_user_by_email(admin_email, authorize?: false) do
    {:ok, user} when not is_nil(user) ->
      user

    _ ->
      Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        email: admin_email,
        confirmed_at: DateTime.utc_now()
      })
      |> Ash.create!(authorize?: false)
  end

Accounts.set_admin!(admin_user, true, authorize?: false)
