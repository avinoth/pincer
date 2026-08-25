# frozen_string_literal: true

# Handles the "Edit goal" button on a GoalDisplay message (draft or
# published): loads the goal referenced by the button value and opens the
# Edit Goal modal, prefilled from it, with the click's fresh trigger_id. The
# origin card's coordinates are threaded through so the modal can update that
# same message in place on submit (see Slack::Views::EditGoalModal, which
# folds `origin` into private_metadata).
class Slack::Interactions::OpenEditGoalModal < Slack::Interactions::Base
  def call
    return unless organization

    goal = organization.goals.find_by(id: action_value)
    return if goal.nil?
    return ephemeral("Only the goal's creator or an owner can edit it.") unless goal.modifiable_by?(user_id)

    view = Slack::Views::EditGoalModal.new(
      goal: goal,
      parent_goals: organization.goals.where(status: [ :not_started, :in_progress ])
        .publishing_published.where.not(id: goal.id).order(:title).limit(50),
      origin: { channel: payload.dig(:channel, :id), message_ts: payload.dig(:container, :message_ts) },
    )
    Slack::Request::OpenView.new(organization.slack_workspace).open_modal(view, trigger_id)
    nil
  end

  private

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end
end
