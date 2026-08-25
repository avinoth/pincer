# frozen_string_literal: true

# Info-only modal shown in place of the (now stale) Create Goal form when the
# "Create Goal" button is clicked after the goal it would have created already
# exists — either a second click on the same button (AgentOpenCreateGoalModal),
# or another user's modal that was open when submission raced it
# (CreateGoalSubmission's replay guard). No submit action: this view only ever
# closes.
#
# `goal` may be nil (the Goal row was deleted since it was produced) — falls
# back to generic copy rather than crashing.
class Slack::Views::GoalAlreadyCreatedModal < Slack::Views::Modal
  def initialize(goal: nil)
    @goal = goal
  end

  def title
    "Goal already created"
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
    return "This goal was already created." if @goal.nil?

    [
      ":white_check_mark: *#{@goal.title}* was already created by #{@goal.creator.full_name}.",
      dates_text
    ].compact.join("\n")
  end

  def dates_text
    return nil if @goal.start_date.blank? || @goal.end_date.blank?

    "#{@goal.start_date.strftime('%b %-d')} – #{@goal.end_date.strftime('%b %-d, %Y')}"
  end
end
