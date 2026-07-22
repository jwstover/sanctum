defmodule Sanctum.Events do
  @moduledoc """
  Standalone organizer tooling for Marvel Champions "God of Lies" Epic
  Multiplayer events.

  This domain is intentionally decoupled from `Sanctum.Games` — it does not
  model or enforce any game mechanics. It is purely the scoreboard the rulebook
  hands a human "event organizer": the three global clocks (Loki's hit points,
  Worlds Collide threat, the time limit) plus the per-pod Mangog / Door Between
  Worlds counters, all derived from a roster of pods, groups, and player counts.
  """
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Events.Event do
      define :create_event, action: :create
      define :get_event, get_by: :id, action: :read
      define :list_events_for_user, action: :read_for_user, args: [:user_id]
      define :update_event, action: :update
      define :start_event, action: :start
      define :adjust_loki_hp, action: :adjust_loki_hp
      define :adjust_worlds_collide, action: :adjust_worlds_collide
      define :reset_timer, action: :reset_timer
      define :destroy_event, action: :destroy
    end

    resource Sanctum.Events.Pod do
      define :create_pod, action: :create
      define :update_pod, action: :update
      define :destroy_pod, action: :destroy
    end

    resource Sanctum.Events.Group do
      define :create_group, action: :create
      define :get_group, get_by: :id, action: :read
      define :update_group, action: :update
      define :adjust_mangog_hp, action: :adjust_mangog_hp
      define :adjust_door_threat, action: :adjust_door_threat
      define :destroy_group, action: :destroy
    end
  end
end
