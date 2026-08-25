class NullifyUserAndOrganizationReferencesOnDelete < ActiveRecord::Migration[8.1]
  # Every place a row points at a User or Organization purely as an
  # attribution/log reference (who created it, who reported it, which org it
  # was logged under) rather than as its reason for existing. These should
  # survive `User#destroy` / `Organization#destroy` with the reference
  # cleared, not block the deletion or vanish with it — matching the policy
  # already applied to initiatives.creator_id.
  def change
    # goals.creator_id: a goal outlives whoever created it.
    change_column_null :goals, :creator_id, true
    add_foreign_key :goals, :users, column: :creator_id, on_delete: :nullify

    # goal_updates.reported_by_id: the timeline entry outlives its reporter.
    change_column_null :goal_updates, :reported_by_id, true
    remove_foreign_key :goal_updates, :users, column: :reported_by_id
    add_foreign_key :goal_updates, :users, column: :reported_by_id, on_delete: :nullify

    # metric_updates.reported_by_id: same — the metric history entry stands on its own.
    add_foreign_key :metric_updates, :users, column: :reported_by_id, on_delete: :nullify

    # conversation_messages.user_id: already nullable (assistant/tool messages
    # have none); a user's own messages stay in the transcript after they leave.
    add_foreign_key :conversation_messages, :users, on_delete: :nullify

    # llm_calls: an observability record — outlives both its user and its org.
    add_foreign_key :llm_calls, :users, on_delete: :nullify
    remove_foreign_key :llm_calls, :organizations
    add_foreign_key :llm_calls, :organizations, on_delete: :nullify

    # slack_interactions.organization_id: append-only interaction log, outlives the org.
    remove_foreign_key :slack_interactions, :organizations
    add_foreign_key :slack_interactions, :organizations, on_delete: :nullify

    # memories.user_id: a user-scoped memory becomes org-scoped rather than disappearing.
    remove_foreign_key :memories, :users
    add_foreign_key :memories, :users, on_delete: :nullify

    # initiatives.owner_id: matches creator_id's existing nullify policy.
    remove_foreign_key :initiatives, :users, column: :owner_id
    add_foreign_key :initiatives, :users, column: :owner_id, on_delete: :nullify

    # organizations.owner_id: no FK existed at all — the designated workspace
    # owner leaving shouldn't block deleting them, or deleting the org.
    add_foreign_key :organizations, :users, column: :owner_id, on_delete: :nullify
  end
end
