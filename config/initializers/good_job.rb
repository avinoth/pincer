# GoodJob cron: recurring jobs the scheduler enqueues on its own, no external
# trigger needed. See https://github.com/bensheldon/good_job#cron-style-repeating-jobs
Rails.application.configure do
  config.good_job.enable_cron = true

  config.good_job.cron = {
    checkin_nudge_scheduler: {
      # Every 15 minutes — CheckinNudgeSchedulerJob's own nudge-window math
      # (see the job) assumes this cadence.
      cron: "*/15 * * * *",
      class: "CheckinNudgeSchedulerJob",
      description: "Nudges goal/initiative owners one day before each goal's weekly summary."
    },
    goal_summary_scheduler: {
      # Every 15 minutes — GoalSummarySchedulerJob's own due?/window math (see
      # the job) assumes this cadence.
      cron: "*/15 * * * *",
      class: "GoalSummarySchedulerJob",
      description: "Posts each in-progress goal's LLM-written weekly summary to its update channel."
    },
    goal_lifecycle_scheduler: {
      # Every 15 minutes — GoalLifecycleSchedulerJob's own due?/window math
      # (see the job) assumes this cadence.
      cron: "*/15 * * * *",
      class: "GoalLifecycleSchedulerJob",
      description: "Flips goal status at start_date/end_date and posts the start/end channel notifications."
    }
  }
end

# GoodJob's dashboard (mounted at /good_job in config/routes.rb) ships with no
# authentication. GoodJob has no native `basic_auth:` config option (as of
# 4.19.2), so this is GoodJob's own documented pattern: gate it with Basic
# Auth via its engine's own middleware stack, using the same shared
# ADMIN_USERNAME/ADMIN_PASSWORD credential as the RailsAdmin panel (see
# api/lib/admin_auth.rb and config/initializers/rails_admin.rb).
GoodJob::Engine.middleware.use(Rack::Auth::Basic, "Admin") { |u, p| AdminAuth.valid?(u, p) }
