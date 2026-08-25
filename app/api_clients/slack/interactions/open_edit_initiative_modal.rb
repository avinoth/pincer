# frozen_string_literal: true

# Handles the "Edit initiative" button on an InitiativeDisplay message: loads
# the initiative referenced by the button value and opens the Edit Initiative
# modal, prefilled from it, with the click's fresh trigger_id. The origin
# card's coordinates are threaded through so the modal can update that same
# message in place on submit (see Slack::Views::EditInitiativeModal, which
# folds `origin` into private_metadata).
class Slack::Interactions::OpenEditInitiativeModal < Slack::Interactions::Base
  def call
    return unless organization

    initiative = organization_initiatives.find_by(id: action_value)
    return if initiative.nil?
    unless initiative.modifiable_by?(user_id)
      return ephemeral("Only the initiative's owner or the goal's owners/creator can edit it.")
    end

    view = Slack::Views::EditInitiativeModal.new(
      initiative: initiative,
      origin: { channel: payload.dig(:channel, :id), message_ts: payload.dig(:container, :message_ts) },
    )
    Slack::Request::OpenView.new(organization.slack_workspace).open_modal(view, trigger_id)
    nil
  end

  private

  # Org-scoped via the parent goal — a stale/foreign initiative id never
  # leaks another org's initiative.
  def organization_initiatives
    Initiative.joins(:goal).where(goals: { organization_id: organization.id })
  end

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end
end
