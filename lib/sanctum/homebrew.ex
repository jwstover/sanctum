defmodule Sanctum.Homebrew do
  @moduledoc """
  Community custom (homebrew) content: projects (the creator's private
  workspace), the publishable sets inside them, their custom cards, and the
  data-driven set kinds (`SetKind`) a project can extend.

  A homebrew card is an image plus optional, progressively-added metadata —
  stored in the same `Card`/`CardSide` tables as the official catalog with
  `origin: :custom` and a `HomebrewSet` FK (the project is reached through the
  set), so browse/search/deckbuilding/
  play work downstream unchanged. Privacy follows the *set*: filter policies on
  `Card`/`CardSide`/`CardAlt`/`Aspect` hide other users' customs whose set is
  not published, while a `HomebrewProject` is a private workspace readable
  only by its creator.

  Homebrew writes are always user-scoped through policies — never the
  `authorize?: false` system-write paths used by catalog sync.

  Custom cards and alt art are `Sanctum.Games.Card`/`CardAlt` rows, so their
  code interfaces live on the `Sanctum.Games` domain
  (`Games.create_custom_card/2`, `Games.declare_custom_alt/4`,
  `Games.list_homebrew_set_cards/2`, ...).
  """

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  resources do
    resource Sanctum.Homebrew.HomebrewProject do
      define :create_project, action: :create
      define :update_project, action: :update
      define :destroy_project, action: :destroy
      define :get_project, action: :read, get_by: [:id]
      define :list_my_projects, action: :for_creator
    end

    resource Sanctum.Homebrew.HomebrewSet do
      define :create_set, action: :create
      define :update_set, action: :update
      define :set_set_visibility, action: :set_visibility, args: [:visibility]
      define :destroy_set, action: :destroy
      define :get_set, action: :read, get_by: [:id]
      define :list_my_sets, action: :for_creator
      define :list_project_sets, action: :by_project, args: [:homebrew_project_id]
      define :list_set_subtree, action: :subtree, args: [:set_id]
      define :set_deletion_impact, action: :deletion_impact, args: [:set_id]
    end

    resource Sanctum.Homebrew.SetKind do
      define :list_set_kinds, action: :read
      define :list_project_set_kinds, action: :for_project, args: [:homebrew_project_id]
      define :create_set_kind, action: :create_custom
      define :update_set_kind, action: :update
      define :destroy_set_kind, action: :destroy
    end
  end
end
