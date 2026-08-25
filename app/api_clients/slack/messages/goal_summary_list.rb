# One message, one colored attachment-card per goal (via Slack::GoalCardPresenter), capped at
# MAX_SUMMARY_CARDS. Overrides Base#to_h because a single #color can only wrap blocks in ONE
# attachment — a list needs one attachment per goal.
class Slack::Messages::GoalSummaryList < Slack::Messages::Base
  VIEW_DETAIL_ACTION_ID = "show_goal_detail"
  MAX_SUMMARY_CARDS = 8

  def initialize(goals:, total:)
    @goals = Array(goals).first(MAX_SUMMARY_CARDS)
    @total = total
  end

  def text
    "#{@total} goal#{'s' unless @total == 1}"
  end

  def to_h
    { text: text, blocks: [ header_block ], attachments: attachments }.compact
  end

  private

  def header_block
    section("*#{@total} goal#{'s' unless @total == 1}*")
  end

  def attachments
    card_attachments = @goals.map { |goal| goal_attachment(goal) }
    card_attachments << overflow_attachment if overflow_count.positive?
    card_attachments
  end

  def goal_attachment(goal)
    presenter = Slack::GoalCardPresenter.new(goal: goal)
    { color: presenter.card_color, blocks: summary_blocks(goal, presenter) }
  end

  def summary_blocks(goal, presenter)
    [
      section(summary_title(goal, presenter)),
      context(summary_context_elements(goal, presenter)),
      actions([ button("View details", action_id: VIEW_DETAIL_ACTION_ID, value: goal.id.to_s) ])
    ]
  end

  def summary_title(goal, presenter)
    lines = [ "#{presenter.status_badge}  *#{goal.title}*" ]
    lines << "`#{presenter.progress_bar}`" if presenter.progress_bar
    lines.join("\n")
  end

  def summary_context_elements(goal, presenter)
    parts = []
    parts << metric_one_liner(goal.metric) if goal.metric
    parts << goal.owners.first&.full_name if goal.owners.any?
    parts << "ends #{goal.end_date.strftime('%b %-d')}" if goal.end_date

    [ mrkdwn(parts.join(" · ")) ]
  end

  def metric_one_liner(metric)
    arrow = metric.direction_decrease? ? "↘︎" : "↗︎"
    "#{metric.name}: #{metric.formatted_current_value} → #{metric.formatted_target_value} #{arrow}"
  end

  def overflow_attachment
    { blocks: [ context([ mrkdwn("…and #{overflow_count} more — ask me to filter") ]) ] }
  end

  def overflow_count
    @total.to_i - @goals.size
  end
end
