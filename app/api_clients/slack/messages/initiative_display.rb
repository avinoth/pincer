# frozen_string_literal: true

# The initiative card: posted fresh into the thread whenever an initiative is
# created or edited (Ai::Agent::Tools::CreateInitiative/EditInitiative, and
# Slack::Interactions::CreateInitiativeSubmission/EditInitiativeSubmission).
# Simpler than GoalDisplay — no metric/pace/health, just the initiative's own
# fields plus a pointer back to its parent goal.
class Slack::Messages::InitiativeDisplay < Slack::Messages::Base
  EDIT_ACTION_ID = "edit_initiative"
  DELETE_ACTION_ID = "delete_initiative"

  INITIATIVE_STATUS_BADGES = {
    "proposed" => "📋 Proposed",
    "in_progress" => "🚧 In progress",
    "done" => "✅ Done",
    "dropped" => "🗑️ Dropped"
  }.freeze

  def initialize(initiative:)
    @initiative = initiative
  end

  def text
    "#{status_label}: #{@initiative.title}"
  end

  def color
    "#DDDDDD"
  end

  def blocks
    [
      header_section,
      description_section,
      details_context,
      actions(action_buttons)
    ].compact
  end

  private

  def status_badge
    INITIATIVE_STATUS_BADGES.fetch(@initiative.status)
  end

  def status_label
    status_badge.split(" ", 2).last
  end

  def header_section
    section("*#{@initiative.title}*\n#{status_badge}")
  end

  def description_section
    section(@initiative.description) if @initiative.description.present?
  end

  def details_context
    elements = [ mrkdwn("👤 #{owner_text}"), mrkdwn("Goal: #{@initiative.goal.title}") ]
    context(elements)
  end

  def owner_text
    @initiative.owner&.full_name || "unassigned"
  end

  def action_buttons
    [
      button("Edit initiative", action_id: EDIT_ACTION_ID, value: @initiative.id.to_s),
      button("Delete initiative", action_id: DELETE_ACTION_ID, value: @initiative.id.to_s, style: "danger", confirm: delete_confirm)
    ]
  end

  # Native Slack confirm dialog — this is the card path's confirmation step
  # (no separate PENDING pause needed, unlike the agent's delete_initiative
  # tool): the user must click through this before
  # Slack::Interactions::DeleteInitiativeAction ever fires.
  def delete_confirm
    {
      title: plain_text("Delete initiative?"),
      text: mrkdwn("This permanently deletes *#{@initiative.title}*. This can't be undone."),
      confirm: plain_text("Delete"),
      deny: plain_text("Cancel"),
      style: "danger"
    }
  end
end
