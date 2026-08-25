# frozen_string_literal: true

# Handles the "Delete initiative" button on an InitiativeDisplay card. The
# native Slack confirm dialog attached to that button (see
# Slack::Messages::InitiativeDisplay#action_buttons) is the user's
# confirmation — by the time this handler runs, they've already clicked
# through it — so this deletes immediately (via ::DeleteInitiative) and
# replaces the card with a tombstone (block_actions carries channel + the
# origin message's ts in `container`, same as Slack::Interactions::PublishGoal).
class Slack::Interactions::DeleteInitiativeAction < Slack::Interactions::Base
  def call
    return unless organization

    initiative = organization_initiatives.find_by(id: action_value)
    return if initiative.nil?
    unless initiative.modifiable_by?(user_id)
      return ephemeral("Only the initiative's owner or the goal's owners/creator can delete it.")
    end

    title = initiative.title
    result = ::DeleteInitiative.call(initiative: initiative)
    return ephemeral("Couldn't delete the initiative: #{result.error}") unless result.success?

    channel = payload.dig(:channel, :id) || payload.dig(:container, :channel_id)
    message_ts = payload.dig(:container, :message_ts) || payload.dig(:message, :ts)

    Slack::Request::UpdateMessage.new(organization.slack_workspace).update_message(
      channel, message_ts, Slack::Messages::InitiativeDeletedNotice.new(title: title).to_h
    )
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
