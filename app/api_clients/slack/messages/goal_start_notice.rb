# The lightweight goal-start notification — no LLM call, nothing to narrate
# yet. Just title/owner(s)/metric target/dates, posted by
# GoalLifecycleSchedulerJob the moment a goal's start_date arrives.
class Slack::Messages::GoalStartNotice < Slack::Messages::Base
  def initialize(goal:)
    @goal = goal
    @presenter = Slack::GoalCardPresenter.new(goal: goal)
  end

  def text
    "#{@goal.title} is now in progress"
  end

  def blocks
    [
      header_section,
      metric_section,
      details_context
    ].compact
  end

  private

  def header_section
    section("*#{@goal.title}* is now in progress 🚀")
  end

  def metric_section
    metric = @goal.metric
    return nil if metric.nil?

    arrow = metric.direction_decrease? ? "↘︎" : "↗︎"
    section("*Target*\n#{metric.name}: #{metric.formatted_current_value} → #{metric.formatted_target_value} #{arrow}")
  end

  def details_context
    elements = @presenter.owners_avatars
    elements << mrkdwn(@presenter.dates_text) if @presenter.dates_text

    return nil if elements.empty?

    context(elements)
  end
end
