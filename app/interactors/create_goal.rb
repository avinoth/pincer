# Persists a Goal from the Create Goal modal: the goal and its owner join
# rows, all in one transaction so a partial goal is never left behind.
#
# Context in:  organization, creator (User), owners (Array<User>), draft
#              (bool, optional), and goal attributes (title, description,
#              start_date, end_date, update_channel, summary_day,
#              summary_time, parent).
# Context out: goal
class CreateGoal
  include Interactor

  def call
    ActiveRecord::Base.transaction do
      goal = context.organization.goals.build(
        creator: context.creator,
        parent: context.parent,
        title: context.title,
        description: context.description,
        start_date: context.start_date,
        end_date: context.end_date,
        update_channel: context.update_channel,
        summary_day: context.summary_day,
        summary_time: context.summary_time,
        status: GoalLifecycle.status_for(context.start_date),
        publishing_status: context.draft ? :draft : :published,
      )
      # Assign owners before saving so the "at least one owner" validation sees
      # them; the join rows are built in memory and persisted with the goal.
      goal.owners = context.owners
      goal.save!

      context.goal = goal
    end
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
