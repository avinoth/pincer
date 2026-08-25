# The weekly outbound check-in nudge: one clubbed DM per owner, covering every
# goal/initiative subject due that tick. `checkins` are all `pending` rows for
# one owner (see CheckinNudgeSchedulerJob/SendCheckinNudgeJob) — grouped here by
# goal so a goal with both a metric subject and initiative subjects renders as
# one block. Mirrors Slack::Messages::GoalSummaryList's one-attachment-per-goal
# shape, but without the button — the reply itself, in this thread, is the CTA.
class Slack::Messages::CheckinNudge < Slack::Messages::Base
  def initialize(checkins:)
    @checkins = Array(checkins)
    @by_goal = @checkins.group_by(&:goal)
  end

  def text
    "Time for a check-in on #{@by_goal.keys.map(&:title).join(', ')}"
  end

  def blocks
    [
      header_section,
      *goal_sections,
      cta_context
    ].compact
  end

  private

  def header_section
    count = @by_goal.size
    section("*Time for a check-in* — #{count} goal#{'s' unless count == 1} due for an update.")
  end

  def goal_sections
    @by_goal.map { |goal, checkins| goal_section(goal, checkins) }
  end

  def goal_section(goal, checkins)
    lines = [ "*#{goal.title}*" ]
    lines << metric_line(goal.metric) if metric_subject?(checkins) && goal.metric
    initiative_lines(checkins).each { |line| lines << line }

    section(lines.join("\n"))
  end

  def metric_subject?(checkins)
    checkins.any? { |checkin| checkin.initiative_id.nil? }
  end

  def metric_line(metric)
    arrow = metric.direction_decrease? ? "↘︎" : "↗︎"
    "#{metric.name}: #{metric.formatted_current_value} → #{metric.formatted_target_value} #{arrow}"
  end

  def initiative_lines(checkins)
    checkins.filter_map(&:initiative).map { |initiative| "• #{initiative.title} — _#{initiative.status}_" }
  end

  def cta_context
    context([ mrkdwn("Reply here to check in — just tell me what's changed.") ])
  end
end
