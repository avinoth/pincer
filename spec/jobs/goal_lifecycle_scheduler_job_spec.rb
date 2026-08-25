require "rails_helper"

RSpec.describe GoalLifecycleSchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, time_zone: "America/Los_Angeles") }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:owner) { create(:user, organization: organization, time_zone: "Asia/Kolkata") }

  let(:slack_response) { { ok: true, ts: "1700000000.000123", channel: "C_UPDATES" }.with_indifferent_access }
  let(:sender) { instance_double(Slack::Request::SendMessage, send_message: slack_response) }

  def moment(date:, time: "09:00", tz: "America/Los_Angeles")
    ActiveSupport::TimeZone[tz].parse("#{date} #{time}")
  end

  before do
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    allow(GenerateGoalSummary).to receive(:call).and_return(double(success?: true, health: "on_track", body: "Cycle complete."))
  end

  describe "start-day branch" do
    let(:goal) do
      create(:goal, organization: organization, owners: [ owner ], title: "Grow activation", status: "not_started",
                    summary_day: 4, summary_time: "09:00", start_date: "2026-08-20", end_date: "2026-08-31",
                    update_channel: "C_UPDATES")
    end
    let!(:metric) { create(:metric, goal: goal) }

    it "flips status to in_progress and posts a kind: start notification with no LLM call" do
      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.to change { GoalNotification.count }.by(1)
      end

      expect(goal.reload).to be_status_in_progress
      notification = GoalNotification.sole
      expect(notification).to be_kind_start
      expect(notification.goal).to eq(goal)
      expect(GenerateGoalSummary).not_to have_received(:call)

      expect(sender).to have_received(:send_message) do |channel, payload|
        expect(channel).to eq("C_UPDATES")
        expect(payload[:blocks].to_s).to include("Grow activation")
      end
      expect(notification.reload.slack_channel_id).to eq("C_UPDATES")
      expect(notification.posted_at).to be_present
    end

    it "does not fire outside the matching 15-minute slot" do
      travel_to(moment(date: "2026-08-20") + 20.minutes) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "does not fire before start_date" do
      travel_to(moment(date: "2026-08-19")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "does not re-fire once the goal is already in_progress" do
      goal.update_column(:status, "in_progress")

      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "is idempotent on a repeated tick" do
      travel_to(moment(date: "2026-08-20")) do
        described_class.perform_now
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
      expect(sender).to have_received(:send_message).once
    end
  end

  describe "end-day branch" do
    let(:goal) do
      create(:goal, organization: organization, owners: [ owner ], title: "Grow activation", status: "in_progress",
                    summary_day: 4, summary_time: "09:00", start_date: "2026-08-01", end_date: "2026-08-20",
                    update_channel: "C_UPDATES")
    end

    it "sets status: completed when the metric's target was reached, and posts the full-cycle narrative" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 45, target_value: 40)
      pending_checkin = create(:checkin, organization: organization, user: owner, goal: goal, status: "pending", period_key: "2026-08-19")

      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.to change { GoalNotification.count }.by(1)
      end

      expect(goal.reload).to be_status_completed
      notification = GoalNotification.sole
      expect(notification).to be_kind_end
      expect(notification.health).to eq("on_track")
      expect(notification.body).to eq("Cycle complete.")
      expect(goal.reload.health).to eq("on_track")
      expect(pending_checkin.reload).to be_status_expired

      expect(GenerateGoalSummary).to have_received(:call) do |args|
        expect(args[:goal]).to eq(goal)
        expect(args[:mode]).to eq(:end)
        expect(args[:period_start]).to eq(goal.start_date)
        expect(args[:period_end]).to eq(goal.end_date)
      end
    end

    it "sets status: ended when the metric's target was not reached" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 25, target_value: 40)

      travel_to(moment(date: "2026-08-20")) { described_class.perform_now }

      expect(goal.reload).to be_status_ended
      expect(GoalNotification.sole).to be_kind_end
    end

    it "does not fire before end_date" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 45, target_value: 40)

      travel_to(moment(date: "2026-08-19")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "does not re-fire once the goal is already in a terminal status" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 45, target_value: 40)
      goal.update_column(:status, "completed")

      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "is idempotent on a repeated tick" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 45, target_value: 40)

      travel_to(moment(date: "2026-08-20")) do
        described_class.perform_now
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
      expect(GenerateGoalSummary).to have_received(:call).once
    end
  end

  describe "goal qualification" do
    it "ignores a draft goal" do
      goal = create(:goal, organization: organization, owners: [ owner ], status: "not_started",
                           summary_time: "09:00", start_date: "2026-08-20", end_date: "2026-08-31")
      goal.update_column(:publishing_status, "draft")

      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "ignores a goal with no summary_time set" do
      create(:goal, organization: organization, owners: [ owner ], status: "not_started",
                    summary_time: nil, start_date: "2026-08-20", end_date: "2026-08-31")

      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end

    it "ignores an inactive organization" do
      create(:goal, organization: organization, owners: [ owner ], status: "not_started",
                    summary_time: "09:00", start_date: "2026-08-20", end_date: "2026-08-31")
      organization.update!(status: "inactive")

      travel_to(moment(date: "2026-08-20")) do
        expect { described_class.perform_now }.not_to change { GoalNotification.count }
      end
    end
  end
end
