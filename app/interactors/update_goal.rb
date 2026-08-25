# Updates an existing Goal — used by both the Edit Goal modal (field edits,
# optionally publishing a draft) and one-click "Publish goal"
# (`UpdateGoal.call(goal:, attributes: {}, publish: true)`). All in one
# transaction so a partial update is never left behind.
#
# Context in:  goal (Goal), attributes (Hash of fields to change, may include
#              :owners), publish (bool).
# Context out: goal
class UpdateGoal
  include Interactor

  def call
    ActiveRecord::Base.transaction do
      goal = context.goal
      attrs = context.attributes.to_h.symbolize_keys
      owners = attrs.delete(:owners)

      goal.assign_attributes(attrs)
      goal.owners = owners if owners
      goal.status = GoalLifecycle.status_for(goal.start_date)
      # Never sets :draft here — the model guard is the safety net against
      # reverting a published goal.
      goal.publishing_status = :published if context.publish

      goal.save!
      context.goal = goal
    end
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
