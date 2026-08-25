# frozen_string_literal: true

# Handles submission of the Edit Initiative modal: parses the modal state
# (fields shared with CreateInitiativeSubmission via InitiativeForm), resolves
# the owner (if one was picked — the field is optional, so the initiative can
# be unassigned), and delegates the update to UpdateInitiative. A single step
# — no wizard push, no in-modal block-action. The parent goal is never
# reassigned.
#
# On success, refreshes the initiative's display in Slack from the modal's
# private_metadata (see Slack::Views::EditInitiativeModal): edited from a card
# → update that card in place; edited from a command (thread context, no
# card) → post a fresh InitiativeDisplay in the thread; neither → nothing to
# refresh.
class Slack::Interactions::EditInitiativeSubmission < Slack::Interactions::Base
  include Slack::Interactions::InitiativeForm

  def call
    return error("title_block", "Please enter a title") if title.blank?
    return unless organization
    return if initiative.nil?
    unless initiative.modifiable_by?(user_id)
      return error("title_block", "You can't edit this initiative.")
    end

    owner = resolve_owner
    result = UpdateInitiative.call(
      initiative: initiative,
      attributes: { title: title, description: description, owner: owner, status: status },
    )
    return error("title_block", "Something went wrong updating the initiative. Please try again.") unless result.success?

    refresh_display(result.initiative)
    { response_action: "clear" }
  end

  private

  # Owner is optional on edit (the field can be left blank to unassign), so
  # only provision a User when one was actually picked.
  def resolve_owner
    return nil if owner_slack_id.blank?

    result = CreateUserFromSlack.call(organization: organization, slack_user_id: owner_slack_id)
    result.success? ? result.user : nil
  end

  def initiative
    @initiative ||= organization_initiatives.find_by(id: metadata["initiative_id"])
  end

  # Org-scoped via the parent goal — a stale/foreign initiative id never
  # leaks another org's initiative.
  def organization_initiatives
    Initiative.joins(:goal).where(goals: { organization_id: organization.id })
  end

  # private_metadata is JSON — { initiative_id, channel?, message_ts?,
  # thread_ts? } — set by Slack::Views::EditInitiativeModal.
  def metadata
    @metadata ||= JSON.parse(payload.dig(:view, :private_metadata))
  end

  def refresh_display(initiative)
    card = Slack::Messages::InitiativeDisplay.new(initiative: initiative).to_h

    if metadata["message_ts"].present?
      Slack::Request::UpdateMessage.new(organization.slack_workspace)
        .update_message(metadata["channel"], metadata["message_ts"], card)
    elsif metadata["channel"].present?
      Slack::Request::SendMessage.new(organization.slack_workspace)
        .send_message(metadata["channel"], card.merge(thread_ts: metadata["thread_ts"]))
    end
  end
end
