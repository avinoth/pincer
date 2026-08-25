# The weekly summary and end-of-cycle closing notification — same rendering
# for both, distinguished only by `mode`'s heading text. The narrative `body`
# is LLM-written (GenerateGoalSummary); this class just lays it out with a
# health badge, mirroring GoalDisplay's badge styling via
# Slack::GoalCardPresenter/HEALTH_COLORS where reusable.
class Slack::Messages::GoalSummary < Slack::Messages::Base
  def initialize(goal:, health:, body:, mode: :weekly)
    @goal = goal
    @health = health
    @body = body
    @mode = mode.to_sym
  end

  def text
    "#{heading}: #{@goal.title}"
  end

  def color
    Slack::GoalCardPresenter::HEALTH_COLORS[@health] || Slack::GoalCardPresenter::HEALTH_COLORS.fetch("on_track")
  end

  def blocks
    [
      header_section,
      body_section,
      metric_context
    ].compact
  end

  private

  def heading
    @mode == :end ? "Goal cycle complete" : "Weekly summary"
  end

  def health_badge
    Slack::Messages::GoalDisplay::HEALTH_BADGES[@health]
  end

  def header_section
    badge_line = [ heading, health_badge ].compact.join("  ·  ")
    section("*#{@goal.title}*\n#{badge_line}")
  end

  def body_section
    section(@body) if @body.present?
  end

  def metric_context
    metric = @goal.metric
    return nil if metric.nil?

    arrow = metric.direction_decrease? ? "↘︎" : "↗︎"
    context([ mrkdwn("#{metric.name}: #{metric.formatted_current_value} → #{metric.formatted_target_value} #{arrow}") ])
  end
end
