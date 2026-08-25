require "rails_helper"

RSpec.describe GoalNotification do
  it { is_expected.to belong_to(:goal) }

  it do
    is_expected.to define_enum_for(:kind)
      .with_values(start: "start", weekly: "weekly", end: "end")
      .backed_by_column_of_type(:string)
      .with_prefix("kind")
  end

  it do
    is_expected.to define_enum_for(:health)
      .with_values(on_track: "on_track", at_risk: "at_risk", off_track: "off_track")
      .backed_by_column_of_type(:string)
      .with_prefix("health")
  end

  it "is readable through the goal" do
    notification = create(:goal_notification)
    expect(notification.goal.goal_notifications).to include(notification)
  end

  it "is destroyed when its goal is destroyed" do
    goal = create(:goal)
    notification = create(:goal_notification, goal: goal)

    goal.destroy!

    expect(GoalNotification.exists?(notification.id)).to eq(false)
  end

  it "enforces one weekly notification per (goal, period)" do
    notification = create(:goal_notification, kind: "weekly", period_key: "2026-08-20")
    duplicate = GoalNotification.new(goal: notification.goal, kind: "weekly", period_key: notification.period_key)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces one start notification per goal" do
    goal = create(:goal)
    create(:goal_notification, goal: goal, kind: "start", period_key: nil)
    duplicate = GoalNotification.new(goal: goal, kind: "start")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces one end notification per goal, independently of start" do
    goal = create(:goal)
    create(:goal_notification, goal: goal, kind: "start", period_key: nil)
    create(:goal_notification, goal: goal, kind: "end", period_key: nil)
    duplicate = GoalNotification.new(goal: goal, kind: "end")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows several weekly notifications for the same goal across different periods" do
    goal = create(:goal)
    create(:goal_notification, goal: goal, kind: "weekly", period_key: "2026-08-13")

    expect { create(:goal_notification, goal: goal, kind: "weekly", period_key: "2026-08-20") }.not_to raise_error
  end
end
