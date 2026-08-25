# Flips one or more Checkin rows to completed, stamping completed_at. Used once
# the agent has captured what a check-in nudge asked for. One transaction so a
# partial completion is never left behind.
#
# Context in:  checkins (Array<Checkin> or ActiveRecord::Relation),
#              user (User — must be every checkin's own owner).
# Context out: checkins
class CompleteCheckin
  include Interactor

  def call
    checkins = Array(context.checkins)
    user = context.user

    return context.fail!(error: "No check-ins given.") if checkins.empty?

    unless checkins.all? { |checkin| checkin.user_id == user&.id }
      return context.fail!(error: "Can only complete your own check-ins.")
    end

    ActiveRecord::Base.transaction do
      checkins.each { |checkin| checkin.update!(status: :completed, completed_at: Time.current) }
    end

    context.checkins = checkins
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end
