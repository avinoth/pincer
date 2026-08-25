# frozen_string_literal: true

# Info-only modal shown in place of the (now stale) Create Initiative form when
# the "Create Initiative" button is clicked after the initiative it would have
# created already exists — either a second click on the same button
# (AgentOpenCreateInitiativeModal), or another user's modal that was open when
# submission raced it (CreateInitiativeSubmission's replay guard). No submit
# action: this view only ever closes.
#
# `initiative` may be nil (the Initiative row was deleted since it was
# produced) — falls back to generic copy rather than crashing.
class Slack::Views::InitiativeAlreadyCreatedModal < Slack::Views::Modal
  def initialize(initiative: nil)
    @initiative = initiative
  end

  def title
    "Initiative already created"
  end

  def submit_label
    nil
  end

  def close_label
    "Close"
  end

  def blocks
    [ section(body_text) ]
  end

  private

  def body_text
    return "This initiative was already created." if @initiative.nil?

    ":white_check_mark: *#{@initiative.title}* was already created under #{@initiative.goal.title}."
  end
end
