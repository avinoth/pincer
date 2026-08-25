# Updates an existing Initiative's title/description/owner/status. The parent
# goal is never reassigned here — an initiative always stays under the goal it
# was created on.
#
# Context in:  initiative (Initiative), attributes (Hash, may include
#              :title, :description, :owner, :status).
# Context out: initiative
class UpdateInitiative
  include Interactor

  def call
    initiative = context.initiative
    attrs = context.attributes.to_h.symbolize_keys
    # The parent goal is never reassigned through this interactor — an
    # initiative always stays under the goal it was created on — so a stray
    # :goal/:goal_id key from a caller is dropped rather than honored.
    attrs.delete(:goal)
    attrs.delete(:goal_id)

    initiative.assign_attributes(attrs)
    initiative.save!

    context.initiative = initiative
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
