# Logs a free-text GoalUpdate(kind: note) against a goal (optionally scoped to
# one of its initiatives). Authorization is broader than a metric/initiative
# mutation: the goal's owner/creator, or the owner of ANY initiative on that
# goal, may leave a note.
#
# Context in:  goal (Goal), body (String), reported_by (User),
#              initiative (Initiative, optional), checkin (Checkin, optional).
# Context out: goal_update
class AddGoalUpdate
  include Interactor

  def call
    goal = context.goal
    reported_by = context.reported_by

    unless authorized?(goal, reported_by)
      return context.fail!(error: "Only the goal's owners/creator, or an initiative owner on this goal, can add a note.")
    end

    goal_update = GoalUpdate.create!(
      checkin: context.checkin,
      goal: goal,
      initiative: context.initiative,
      reported_by: reported_by,
      kind: :note,
      body: context.body,
    )

    context.goal_update = goal_update
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end

  private

  def authorized?(goal, reported_by)
    return false if goal.blank? || reported_by&.provider_uid.blank?

    goal.modifiable_by?(reported_by.provider_uid) ||
      goal.initiatives.where(owner_id: reported_by.id).exists?
  end
end
