require "rails_helper"

RSpec.describe GoalSummarySchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, time_zone: "America/Los_Angeles") }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:owner) { create(:user, organization: organization, time_zone: "Asia/Kolkata") }
  let(:goal) do
    create(:goal, organization: organization, owners: [ owner ], title: "Grow activation", status: "in_progress",
                  summary_day: 4, summary_time: "17:00", start_date: "2026-08-01", end_date: "2026-08-31",
                  update_channel: "C_UPDATES")
  end
  let!(:metric) { create(:metric, goal: goal) }

  let(:slack_response) { { ok: true, ts: "1700000000.000123", channel: "C_UPDATES" }.with_indifferent_access }
  let(:sender) { instance_double(Slack::Request::SendMessage, send_message: slack_response) }

  def summary_moment(tz = "America/Los_Angeles", date: "2026-08-20", time: "17:00")
    # 2026-08-20 is a Thursday (wday 4) -- matches goal.summary_day above.
    ActiveSupport::TimeZone[tz].parse("#{date} #{time}")
  end

  before do
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    allow(GenerateGoalSummary).to receive(:call).and_return(double(success?: true, health: "on_track", body: "Solid week."))
  end

  describe "due? timing, keyed off the ORGANIZATION's own time zone" do
    it "fires at summary_time on summary_day, in the organization's zone (not the owner's)" do
      travel_to(summary_moment) do
        expect { described_class.perform_now }.to change { GoalNotification.count }.by(1)
      end

      notification = GoalNotification.sole
      expect(notification).to be_kind_weekly
      expect(notification.goal).to eq(goal)
      expect(notification.period_key).to eq("2026-08-20")
    end

    it "does not fire outside the matching 15-minute slot" do
      travel_to(summary_moment + 20.minutes) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end

      travel_to(summary_moment - 1.minute) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "does not fire on a day that isn't summary_day" do
      travel_to(summary_moment(date: "2026-08-21")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end
  end

  describe "idempotency" do
    it "does not double-post on a second tick within the same window (unique index)" do
      travel_to(summary_moment) do
        described_class.perform_now
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end

      expect(GoalNotification.count).to eq(1)
      expect(sender).to have_received(:send_message).once
    end
  end

  describe "Checkin#expired transition" do
    it "flips the goal's still pending/notified Checkins to expired" do
      other_owner = create(:user, organization: organization)
      pending_checkin = create(:checkin, organization: organization, user: owner, goal: goal, status: "pending", period_key: "2026-08-19")
      notified_checkin = create(:checkin, organization: organization, user: other_owner, goal: goal, status: "notified", period_key: "2026-08-19")
      already_completed = create(:checkin, organization: organization, user: owner, goal: goal, status: "completed", period_key: "2026-08-12")

      travel_to(summary_moment) { described_class.perform_now }

      expect(pending_checkin.reload).to be_status_expired
      expect(notified_checkin.reload).to be_status_expired
      expect(already_completed.reload).to be_status_completed
    end
  end

  describe "generating and posting the summary" do
    it "calls GenerateGoalSummary over the trailing week and persists health/body onto the notification and Goal#health" do
      travel_to(summary_moment) { described_class.perform_now }

      expect(GenerateGoalSummary).to have_received(:call) do |args|
        expect(args[:goal]).to eq(goal)
        expect(args[:mode]).to eq(:weekly)
        expect(args[:period_end]).to eq(summary_moment)
        expect(args[:period_start]).to eq(summary_moment - 7.days)
      end

      notification = GoalNotification.sole
      expect(notification.health).to eq("on_track")
      expect(notification.body).to eq("Solid week.")
      expect(goal.reload.health).to eq("on_track")
    end

    it "posts to goal.update_channel and stamps the notification" do
      travel_to(summary_moment) { described_class.perform_now }

      expect(sender).to have_received(:send_message) do |channel, payload|
        expect(channel).to eq("C_UPDATES")
        expect(payload[:attachments].first[:blocks].to_s).to include("Solid week.")
      end

      notification = GoalNotification.sole
      expect(notification.slack_channel_id).to eq("C_UPDATES")
      expect(notification.slack_thread_ts).to eq("1700000000.000123")
      expect(notification.posted_at).to be_present
    end

    it "still persists health/body when the goal has no update_channel (safe no-op post)" do
      # Mirrors Slack::Request::SendMessage#send_message's real behavior: a
      # blank channel_id is a no-op returning nil, never hitting the API.
      allow(sender).to receive(:send_message).with(nil, anything).and_return(nil)
      goal.update_column(:update_channel, nil)

      travel_to(summary_moment) { described_class.perform_now }

      notification = GoalNotification.sole
      expect(notification.body).to eq("Solid week.")
      expect(notification.posted_at).to be_nil
    end
  end

  describe "goal qualification" do
    it "ignores a draft goal" do
      goal.update_column(:publishing_status, "draft")

      travel_to(summary_moment) { described_class.perform_now }

      expect(GoalNotification.count).to eq(0)
    end

    it "ignores a goal that isn't in_progress" do
      goal.update_column(:status, "completed")

      travel_to(summary_moment) { described_class.perform_now }

      expect(GoalNotification.count).to eq(0)
    end

    it "ignores a goal outside its start/end date range" do
      goal.update_columns(start_date: "2026-09-01", end_date: "2026-09-30")

      travel_to(summary_moment) { described_class.perform_now }

      expect(GoalNotification.count).to eq(0)
    end

    it "ignores an inactive organization" do
      organization.update!(status: "inactive")

      travel_to(summary_moment) { described_class.perform_now }

      expect(GoalNotification.count).to eq(0)
    end
  end
end
