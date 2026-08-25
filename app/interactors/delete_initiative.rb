# Hard-deletes an Initiative. The single place initiative deletion happens —
# both the agent's confirm-first delete_initiative tool flow
# (Slack::Interactions::AgentConfirmDeleteInitiative) and the
# InitiativeDisplay card's own Delete button
# (Slack::Interactions::DeleteInitiativeAction) converge here. Irreversible:
# dependent Checkins and GoalUpdates cascade via the model's `dependent:
# :destroy` associations.
#
# Context in:  initiative (Initiative)
# Context out: deleted_title, goal_title — captured before the destroy, for
#              convenience. Callers that need the title/goal after this
#              returns should still capture it themselves before calling,
#              since the record itself is gone once this succeeds.
class DeleteInitiative
  include Interactor

  def call
    initiative = context.initiative
    context.deleted_title = initiative.title
    context.goal_title = initiative.goal.title

    initiative.destroy!
  rescue StandardError => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
