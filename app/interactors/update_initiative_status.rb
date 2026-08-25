# Changes an Initiative's status (e.g. marking it done) and logs a
# GoalUpdate(kind: initiative_status) narrating the change. One transaction so
# a partial write is never left behind.
#
# Context in:  initiative (Initiative), status (String), reported_by (User),
#              checkin (Checkin, optional — the nudge this report answers).
# Context out: initiative, goal_update
class UpdateInitiativeStatus
  include Interactor

  def call
    initiative = context.initiative
    reported_by = context.reported_by

    unless initiative&.modifiable_by?(reported_by&.provider_uid)
      return context.fail!(error: "Only the initiative's owner or the goal's owners/creator can update it.")
    end

    unless Initiative.statuses.key?(context.status.to_s)
      return context.fail!(error: "\"#{context.status}\" isn't a valid initiative status " \
                                   "(#{Initiative.statuses.keys.join(', ')}).")
    end

    ActiveRecord::Base.transaction do
      previous_status = initiative.status
      initiative.update!(status: context.status)

      goal_update = GoalUpdate.create!(
        checkin: context.checkin,
        goal: initiative.goal,
        initiative: initiative,
        reported_by: reported_by,
        kind: :initiative_status,
        body: "\"#{initiative.title}\": #{previous_status} → #{initiative.status}",
      )

      context.initiative = initiative
      context.goal_update = goal_update
    end
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
