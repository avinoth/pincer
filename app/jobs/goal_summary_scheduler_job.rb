# GoodJob cron tick (every 15 minutes, see config/initializers/good_job.rb):
# finds every in-progress, published goal due its weekly summary RIGHT NOW —
# today (in the goal's own ORGANIZATION's time zone, since this posts to a
# channel with no single recipient) is the goal's summary_day, and now is in
# the 15-minute slot containing summary_time.
#
# On the tick that creates the GoalNotification(kind: weekly) row (idempotent
# via the unique index on goal_id/kind/period_key — see the
# CheckinNudgeSchedulerJob comment for why find_or_create_by! +
# previously_new_record? gives us that for free): closes out any Checkins for
# this goal still pending/notified -> expired (this is what makes the week's
# gaps narratable), gathers the trailing week's GoalUpdate/MetricUpdate/
# expired-Checkin data, calls GenerateGoalSummary for the narrative + health
# classification, persists both onto the notification AND Goal#health, posts
# to goal.update_channel, and stamps the post.
class GoalSummarySchedulerJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  queue_as :default

  # A tick that's still running when the next one fires must not overlap it —
  # overlap could double-post the same weekly summary before the first tick's
  # find_or_create_by! has a chance to make the second one a no-op.
  good_job_control_concurrency_with(perform_limit: 1, key: -> { "goal-summary-scheduler" })

  TICK_INTERVAL = 15.minutes
  # The window a weekly summary covers — the goal's summary recurs on the same
  # local weekday every week, so "this period" is always the trailing 7 days.
  PERIOD_LENGTH = 7.days

  def perform
    Organization.active.find_each do |organization|
      qualifying_goals(organization).find_each { |goal| process_goal(goal, organization) }
    end
  end

  private

  def qualifying_goals(organization)
    organization.goals
      .publishing_published
      .status_in_progress
      .where.not(summary_day: nil)
      .where.not(summary_time: nil)
      .where("start_date <= ? AND end_date >= ?", Date.current, Date.current)
  end

  def process_goal(goal, organization)
    moment = summary_moment_for(goal, organization)
    return unless due?(moment)

    notification = GoalNotification.find_or_create_by!(goal: goal, kind: :weekly, period_key: period_key_for(moment))
    return unless notification.previously_new_record?

    generate_and_post(goal: goal, notification: notification, period_start: moment - PERIOD_LENGTH, period_end: moment)
  end

  # Today's summary_time, in the ORGANIZATION's own time zone (not the
  # owner's — there's no single recipient for a channel post). Falls back to
  # UTC for an unrecognized zone string rather than raising. Due only when
  # today (org-local) is this goal's summary_day.
  def summary_moment_for(goal, organization)
    zone = ActiveSupport::TimeZone[organization.time_zone] || ActiveSupport::TimeZone["UTC"]
    today_local = zone.now.to_date
    return nil unless today_local.wday == goal.summary_day

    zone.parse("#{today_local.iso8601} #{goal.summary_time}")
  rescue ArgumentError, TypeError
    nil
  end

  # True when `moment` falls in the 15-minute slot ending now — i.e. this is
  # the one tick that owns this moment.
  def due?(moment)
    return false if moment.nil?

    now = Time.current
    moment > (now - TICK_INTERVAL) && moment <= now
  end

  def period_key_for(moment)
    moment.to_date.iso8601
  end

  def generate_and_post(goal:, notification:, period_start:, period_end:)
    expire_stale_checkins(goal)

    result = GenerateGoalSummary.call(goal: goal, period_start: period_start, period_end: period_end, mode: :weekly)
    return unless result.success?

    notification.update!(health: result.health, body: result.body)
    goal.update!(health: result.health)

    post(goal, notification, result.health, result.body)
  end

  def expire_stale_checkins(goal)
    goal.checkins.where(status: %w[pending notified]).update_all(status: "expired", updated_at: Time.current)
  end

  def post(goal, notification, health, body)
    workspace = goal.organization.slack_workspace
    return unless workspace

    response = Slack::Request::SendMessage.new(workspace).send_message(
      goal.update_channel,
      Slack::Messages::GoalSummary.new(goal: goal, health: health, body: body, mode: :weekly).to_h,
    )
    return if response.blank?

    notification.update!(
      slack_channel_id: response[:channel],
      slack_thread_ts: response[:ts],
      posted_at: Time.current,
    )
  end
end
