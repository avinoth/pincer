# GoodJob cron tick (every 15 minutes, see config/initializers/good_job.rb):
# finds every (goal, subject, owner) that's due its "one day before the weekly
# summary" nudge RIGHT NOW, in that owner's own time zone, upserts a Checkin
# per due subject, then enqueues one clubbed SendCheckinNudgeJob per owner for
# whatever Checkins this tick actually created.
#
# A goal's weekly summary recurs on the same local weekday every week, so the
# nudge — one day earlier — also recurs on a fixed weekday: no "which week is
# this" bookkeeping is needed, just "is today (in the owner's zone) the day
# before summary_day, and are we within the 15-minute slot containing
# summary_time minus one day."
#
# Subjects per goal: the goal's metric (one subject per goal owner) and each
# initiative (one subject for its own owner, piggybacked on the parent goal's
# schedule). The metric subject is suppressed ("not nosy") when a MetricUpdate
# already landed in the trailing week ending at the nudge moment — the owner
# already reported, no need to nag.
class CheckinNudgeSchedulerJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  queue_as :default

  # A tick that's still running when the next one fires must not overlap it —
  # ticks are idempotent via the Checkin unique indexes, but overlap could
  # still double-enqueue SendCheckinNudgeJob for the same freshly created rows.
  good_job_control_concurrency_with(perform_limit: 1, key: -> { "checkin-nudge-scheduler" })

  # How far back "already reported this period" looks, from the nudge moment.
  SUPPRESSION_WINDOW = 7.days
  # The tick cadence — defines the matching window around each candidate nudge
  # moment (see #due?).
  TICK_INTERVAL = 15.minutes

  def perform
    Organization.active.find_each do |organization|
      qualifying_goals(organization).find_each { |goal| process_goal(goal) }
    end
  end

  private

  def qualifying_goals(organization)
    organization.goals
      .publishing_published
      .status_in_progress
      .joins(:metric)
      .where.not(summary_day: nil)
      .where.not(summary_time: nil)
      .where("start_date <= ? AND end_date >= ?", Date.current, Date.current)
  end

  def process_goal(goal)
    created = []
    created.concat(process_metric_subject(goal))
    goal.initiatives.each { |initiative| created.concat(process_initiative_subject(goal, initiative)) }

    created.group_by(&:user_id).each_value do |owner_checkins|
      SendCheckinNudgeJob.perform_later(user_id: owner_checkins.first.user_id, checkin_ids: owner_checkins.map(&:id))
    end
  end

  def process_metric_subject(goal)
    goal.owners.filter_map do |owner|
      nudge_moment = nudge_moment_for(goal, owner)
      next unless due?(nudge_moment)
      next if metric_already_reported?(goal.metric, nudge_moment)

      upsert_checkin(goal: goal, initiative: nil, user: owner, period_key: period_key_for(nudge_moment))
    end
  end

  def process_initiative_subject(goal, initiative)
    owner = initiative.owner
    return [] unless owner

    nudge_moment = nudge_moment_for(goal, owner)
    return [] unless due?(nudge_moment)

    [ upsert_checkin(goal: goal, initiative: initiative, user: owner, period_key: period_key_for(nudge_moment)) ]
  end

  # The nudge moment: one day before this goal's next summary_day/summary_time,
  # localized to the owner's own time zone. Falls back to UTC for an
  # unrecognized zone string rather than raising.
  def nudge_moment_for(goal, owner)
    zone = ActiveSupport::TimeZone[owner.time_zone] || ActiveSupport::TimeZone["UTC"]
    today_local = zone.now.to_date
    nudge_weekday = (goal.summary_day - 1) % 7
    return nil unless today_local.wday == nudge_weekday

    zone.parse("#{today_local.iso8601} #{goal.summary_time}")
  rescue ArgumentError, TypeError
    nil
  end

  # True when `nudge_moment` falls in the 15-minute slot ending now — i.e. this
  # is the one tick that owns this nudge moment.
  def due?(nudge_moment)
    return false if nudge_moment.nil?

    now = Time.current
    nudge_moment > (now - TICK_INTERVAL) && nudge_moment <= now
  end

  def metric_already_reported?(metric, nudge_moment)
    metric.metric_updates.where(created_at: (nudge_moment - SUPPRESSION_WINDOW)..nudge_moment).exists?
  end

  def period_key_for(nudge_moment)
    nudge_moment.to_date.iso8601
  end

  # find_or_create_by! against the (partial) unique index makes a repeated tick
  # a no-op; `previously_new_record?` tells the caller whether THIS tick is the
  # one that actually created it, so we only notify for fresh rows.
  def upsert_checkin(goal:, initiative:, user:, period_key:)
    checkin = Checkin.find_or_create_by!(
      goal: goal, initiative: initiative, user: user, period_key: period_key,
    ) do |c|
      c.organization = goal.organization
      c.status = :pending
    end
    checkin.previously_new_record? ? checkin : nil
  end
end
