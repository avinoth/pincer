# Persists an Initiative under a goal — either straight from the agent
# (Ai::Agent::Tools::CreateInitiative) or from the Create Initiative modal
# submission. Refuses to attach to a goal in a terminal lifecycle state
# (completed/ended) — see Goal#accepts_initiatives?.
#
# Context in:  goal (Goal), creator (User), owner (User, optional), title,
#              description (optional).
# Context out: initiative
class CreateInitiative
  include Interactor

  def call
    unless context.goal.accepts_initiatives?
      return context.fail!(
        error: "#{context.goal.title} is #{context.goal.status.humanize.downcase} and can't take new initiatives."
      )
    end

    initiative = context.goal.initiatives.build(
      creator: context.creator,
      owner: context.owner,
      title: context.title,
      description: context.description,
      status: :proposed,
    )
    initiative.save!

    context.initiative = initiative
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
