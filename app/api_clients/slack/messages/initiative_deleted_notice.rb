# frozen_string_literal: true

# Minimal tombstone shown in place of a deleted initiative's card — replaces
# the InitiativeDisplay message via UpdateMessage. Shared by both delete
# surfaces: the card's own Delete button
# (Slack::Interactions::DeleteInitiativeAction) and the agent's confirm-first
# flow (Slack::Interactions::AgentConfirmDeleteInitiative).
class Slack::Messages::InitiativeDeletedNotice < Slack::Messages::Base
  def initialize(title: nil)
    @title = title
  end

  def text
    body
  end

  def blocks
    [ section(body) ]
  end

  private

  def body
    @title.present? ? "🗑️ Initiative *#{@title}* deleted." : "🗑️ This initiative has been deleted."
  end
end
