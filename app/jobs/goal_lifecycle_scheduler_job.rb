# GoodJob cron tick (every 15 minutes, see config/initializers/good_job.rb):
# the only thing that actually drives a goal from not_started -> in_progress
# and from in_progress -> completed/ended on a schedule (today, Goal#status
# otherwise only updates lazily whenever a goal happens to be saved). Finds
# every published goal due its start-day or end-day post RIGHT NOW — today (in
# the goal's own ORGANIZATION's time zone, same rationale as
# GoalSummarySchedulerJob) matches start_date (goal still not_started) or
# end_date (goal still in_progress), and now is in the 15-minute slot
# containing summary_time (reused as the daily "posting clock" for all three
# notification kinds).
#
# Start: GoalNotification(kind: start) is idempotent per-goal (unique index on
# goal_id/kind, no period_key needed — one-time). On the tick that creates it,
# flips status: in_progress and posts a lightweight, no-LLM template.
#
# End: GoalNotification(kind: end), same one-time idempotency. On the tick
# that creates it, decides completed/ended via the now-activated
# GoalLifecycle#outcome_for, closes out stale Checkins, gathers the entire
# cycle's history (from start_date, not just the last period), and calls
# GenerateGoalSummary with a closing framing (mode: :end) for the narrative +
# final health classification.
class GoalLifecycleSchedulerJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  queue_as :default

  good_job_control_concurrency_with(perform_limit: 1, key: -> { "goal-lifecycle-scheduler" })

  TICK_INTERVAL = 15.minutes

  def perform
    Organization.active.find_each do |organization|
      qualifying_goals(organization).find_each { |goal| process_goal(goal, organization) }
    end
  end

  private

  def qualifying_goals(organization)
    organization.goals.publishing_published.where.not(summary_time: nil)
  end

  def process_goal(goal, organization)
    moment = daily_moment_for(goal, organization)
    return unless due?(moment)

    today_local = moment.to_date
    if goal.status_not_started? && goal.start_date == today_local
      process_start(goal)
    elsif goal.status_in_progress? && goal.end_date == today_local
      process_end(goal)
    end
  end

  # Today's summary_time, in the ORGANIZATION's own time zone. Falls back to
  # UTC for an unrecognized zone string rather than raising.
  def daily_moment_for(goal, organization)
    zone = ActiveSupport::TimeZone[organization.time_zone] || ActiveSupport::TimeZone["UTC"]
    today_local = zone.now.to_date
    zone.parse("#{today_local.iso8601} #{goal.summary_time}")
  rescue ArgumentError, TypeError
    nil
  end

  def due?(moment)
    return false if moment.nil?

    now = Time.current
    moment > (now - TICK_INTERVAL) && moment <= now
  end

  def process_start(goal)
    notification = GoalNotification.find_or_create_by!(goal: goal, kind: :start)
    return unless notification.previously_new_record?

    goal.update!(status: :in_progress)
    post_start(goal, notification)
  end

  def post_start(goal, notification)
    workspace = goal.organization.slack_workspace
    return unless workspace

    response = Slack::Request::SendMessage.new(workspace).send_message(
      goal.update_channel,
      Slack::Messages::GoalStartNotice.new(goal: goal).to_h,
    )
    return if response.blank?

    notification.update!(
      slack_channel_id: response[:channel],
      slack_thread_ts: response[:ts],
      posted_at: Time.current,
    )
  end

  def process_end(goal)
    notification = GoalNotification.find_or_create_by!(goal: goal, kind: :end)
    return unless notification.previously_new_record?

    outcome = GoalLifecycle.outcome_for(goal)
    goal.update!(status: outcome)

    expire_stale_checkins(goal)

    result = GenerateGoalSummary.call(goal: goal, period_start: goal.start_date, period_end: goal.end_date, mode: :end)
    return unless result.success?

    notification.update!(health: result.health, body: result.body)
    goal.update!(health: result.health)

    post_end(goal, notification, result.health, result.body)
  end

  def expire_stale_checkins(goal)
    goal.checkins.where(status: %w[pending notified]).update_all(status: "expired", updated_at: Time.current)
  end

  def post_end(goal, notification, health, body)
    workspace = goal.organization.slack_workspace
    return unless workspace

    response = Slack::Request::SendMessage.new(workspace).send_message(
      goal.update_channel,
      Slack::Messages::GoalSummary.new(goal: goal, health: health, body: body, mode: :end).to_h,
    )
    return if response.blank?

    notification.update!(
      slack_channel_id: response[:channel],
      slack_thread_ts: response[:ts],
      posted_at: Time.current,
    )
  end
end
