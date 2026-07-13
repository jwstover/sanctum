defmodule Sanctum.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sanctum.Accounts` context.
  """

  def user_fixture(attrs \\ %{}) do
    email = attrs[:email] || Faker.Internet.email()

    attrs = %{
      email: email,
      confirmed_at: attrs[:confirmed_at] || DateTime.utc_now()
    }

    # Skip authorization for test fixtures
    Sanctum.Accounts.User
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(authorize?: false)
  end

  def admin_user_fixture(attrs \\ %{}) do
    attrs
    |> user_fixture()
    |> Ash.Changeset.for_update(:set_admin, %{admin: true})
    |> Ash.update!(authorize?: false)
  end
end
