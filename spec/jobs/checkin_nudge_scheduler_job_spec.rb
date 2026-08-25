require "rails_helper"

RSpec.describe CheckinNudgeSchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }

  def build_goal(time_zone:, summary_day: 5, summary_time: "17:00")
    owner = create(:user, organization: organization, time_zone: time_zone)
    goal = create(:goal, organization: organization, owners: [ owner ], status: "in_progress",
                         summary_day: summary_day, summary_time: summary_time,
                         start_date: "2026-08-01", end_date: "2026-08-31")
    create(:metric, goal: goal)
    [ goal, owner ]
  end

  def nudge_moment(time_zone, date: "2026-08-20", time: "17:00")
    ActiveSupport::TimeZone[time_zone].parse("#{date} #{time}")
  end

  describe "nudge timing, localized per owner" do
    it "fires a goal's nudge at summary_time minus one day, independently in two owners' own time zones" do
      la_goal, la_owner = build_goal(time_zone: "America/Los_Angeles")

      travel_to(nudge_moment("America/Los_Angeles")) do
        expect { described_class.perform_now }.to change { Checkin.count }.by(1)
      end

      la_checkin = Checkin.sole
      expect(la_checkin.goal).to eq(la_goal)
      expect(la_checkin.user).to eq(la_owner)
      expect(la_checkin.initiative_id).to be_nil
      expect(la_checkin.period_key).to eq("2026-08-20")
      expect(la_checkin).to be_status_pending

      kolkata_goal, kolkata_owner = build_goal(time_zone: "Asia/Kolkata")

      # The LA moment above is a completely different real instant than
      # Kolkata's own 17:00 — advancing to Kolkata's nudge moment must fire
      # ONLY the Kolkata goal, not re-fire (or skip) the LA one.
      travel_to(nudge_moment("Asia/Kolkata")) do
        expect { described_class.perform_now }.to change { Checkin.count }.by(1)
      end

      kolkata_checkin = Checkin.where(goal: kolkata_goal).sole
      expect(kolkata_checkin.user).to eq(kolkata_owner)
      expect(kolkata_checkin.period_key).to eq("2026-08-20")
      # Still just the one LA checkin from earlier — not duplicated.
      expect(Checkin.where(goal: la_goal).count).to eq(1)
    end

    it "does not fire outside the matching 15-minute slot" do
      build_goal(time_zone: "UTC")

      travel_to(nudge_moment("UTC") + 20.minutes) do
        expect { described_class.perform_now }.not_to change { Checkin.count }
      end

      travel_to(nudge_moment("UTC") - 1.minute) do
        expect { described_class.perform_now }.not_to change { Checkin.count }
      end
    end
  end

  describe "idempotency" do
    it "does not double-nudge on a second tick within the same window (unique index)" do
      build_goal(time_zone: "UTC")

      travel_to(nudge_moment("UTC")) do
        described_class.perform_now
        expect { described_class.perform_now }.not_to change { Checkin.count }
      end

      expect(Checkin.count).to eq(1)
    end

    it "enqueues exactly one SendCheckinNudgeJob per owner even if the tick somehow re-runs" do
      build_goal(time_zone: "UTC")

      travel_to(nudge_moment("UTC")) do
        described_class.perform_now
        described_class.perform_now
      end

      expect(enqueued_jobs.count { |j| j["job_class"] == "SendCheckinNudgeJob" }).to eq(1)
    end
  end

  describe "metric-subject suppression" do
    it "skips the metric subject when a MetricUpdate already landed in the trailing week" do
      goal, owner = build_goal(time_zone: "UTC")
      moment = nudge_moment("UTC")
      create(:metric_update, metric: goal.metric, reported_by: owner, created_at: moment - 2.days)

      travel_to(moment) do
        expect { described_class.perform_now }.not_to change { Checkin.count }
      end
    end

    it "still fires when the last MetricUpdate is older than the suppression window" do
      goal, owner = build_goal(time_zone: "UTC")
      moment = nudge_moment("UTC")
      create(:metric_update, metric: goal.metric, reported_by: owner, created_at: moment - 30.days)

      travel_to(moment) do
        expect { described_class.perform_now }.to change { Checkin.count }.by(1)
      end
    end

    it "does not suppress an initiative subject just because the goal's metric was reported" do
      goal, owner = build_goal(time_zone: "UTC")
      moment = nudge_moment("UTC")
      create(:metric_update, metric: goal.metric, reported_by: owner, created_at: moment - 1.day)
      initiative = create(:initiative, goal: goal, owner: owner)

      travel_to(moment) do
        expect { described_class.perform_now }.to change { Checkin.count }.by(1)
      end

      checkin = Checkin.sole
      expect(checkin.initiative).to eq(initiative)
    end
  end

  describe "subjects and clubbing" do
    it "creates one checkin for the metric and one per initiative, clubbed under one SendCheckinNudgeJob per owner" do
      goal, owner = build_goal(time_zone: "UTC")
      initiative = create(:initiative, goal: goal, owner: owner)
      other_owner = create(:user, organization: organization, time_zone: "UTC")
      other_initiative = create(:initiative, goal: goal, owner: other_owner)

      travel_to(nudge_moment("UTC")) do
        described_class.perform_now
      end

      expect(Checkin.where(user: owner).count).to eq(2) # metric + own initiative
      expect(Checkin.where(user: other_owner).count).to eq(1) # other initiative only

      owner_job = enqueued_jobs.find { |j| j["job_class"] == "SendCheckinNudgeJob" && j["arguments"].first["user_id"] == owner.id }
      expect(owner_job["arguments"].first["checkin_ids"].size).to eq(2)
    end

    it "skips an initiative with no owner (nobody to nudge)" do
      goal, _owner = build_goal(time_zone: "UTC")
      create(:initiative, goal: goal, owner: nil)

      travel_to(nudge_moment("UTC")) do
        described_class.perform_now
      end

      expect(Checkin.where(initiative_id: nil).count).to eq(1) # metric subject only
    end
  end

  describe "goal qualification" do
    it "ignores a draft goal" do
      goal, _owner = build_goal(time_zone: "UTC")
      goal.update_column(:publishing_status, "draft")

      travel_to(nudge_moment("UTC")) { described_class.perform_now }

      expect(Checkin.count).to eq(0)
    end

    it "ignores a goal that isn't in_progress" do
      goal, _owner = build_goal(time_zone: "UTC")
      goal.update_column(:status, "completed")

      travel_to(nudge_moment("UTC")) { described_class.perform_now }

      expect(Checkin.count).to eq(0)
    end

    it "ignores a goal with no metric" do
      owner = create(:user, organization: organization, time_zone: "UTC")
      create(:goal, organization: organization, owners: [ owner ], status: "in_progress",
                    summary_day: 5, summary_time: "17:00", start_date: "2026-08-01", end_date: "2026-08-31")

      travel_to(nudge_moment("UTC")) { described_class.perform_now }

      expect(Checkin.count).to eq(0)
    end

    it "ignores a goal outside its start/end date range" do
      goal, _owner = build_goal(time_zone: "UTC")
      goal.update_columns(start_date: "2026-09-01", end_date: "2026-09-30")

      travel_to(nudge_moment("UTC")) { described_class.perform_now }

      expect(Checkin.count).to eq(0)
    end

    it "ignores an inactive organization" do
      build_goal(time_zone: "UTC")
      organization.update!(status: "inactive")

      travel_to(nudge_moment("UTC")) { described_class.perform_now }

      expect(Checkin.count).to eq(0)
    end
  end
end
