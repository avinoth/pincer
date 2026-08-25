require "rails_helper"

RSpec.describe Checkin do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:goal) }
  it { is_expected.to belong_to(:initiative).optional }

  it { is_expected.to validate_presence_of(:period_key) }

  it do
    is_expected.to define_enum_for(:status)
      .with_values(
        pending: "pending",
        notified: "notified",
        in_progress: "in_progress",
        completed: "completed",
        skipped: "skipped",
        expired: "expired")
      .backed_by_column_of_type(:string)
      .with_prefix("status")
  end

  it "defaults to pending" do
    checkin = create(:checkin)
    expect(checkin).to be_status_pending
  end

  it "is readable through the owner, goal, and (when set) initiative" do
    checkin = create(:checkin)
    expect(checkin.user.checkins).to include(checkin)
    expect(checkin.goal.checkins).to include(checkin)

    initiative = create(:initiative, goal: checkin.goal)
    initiative_checkin = create(:checkin, organization: checkin.organization, user: checkin.user,
                                goal: checkin.goal, initiative: initiative, period_key: "2026-08-21")
    expect(initiative.checkins).to include(initiative_checkin)
  end

  it "enforces one metric-subject checkin per (goal, user, period)" do
    checkin = create(:checkin)
    duplicate = Checkin.new(organization: checkin.organization, user: checkin.user, goal: checkin.goal,
                            period_key: checkin.period_key)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces one initiative-subject checkin per (goal, user, initiative, period), independent of the metric subject" do
    goal = create(:goal)
    user = create(:user, organization: goal.organization)
    initiative = create(:initiative, goal: goal)
    period_key = "2026-08-20"
    create(:checkin, organization: goal.organization, user: user, goal: goal, period_key: period_key)
    create(:checkin, organization: goal.organization, user: user, goal: goal, initiative: initiative, period_key: period_key)

    duplicate = Checkin.new(organization: goal.organization, user: user, goal: goal, initiative: initiative,
                            period_key: period_key)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "nullifies (not destroys) its GoalUpdates when destroyed" do
    checkin = create(:checkin)
    goal_update = create(:goal_update, checkin: checkin, goal: checkin.goal)

    checkin.destroy!

    expect(GoalUpdate.exists?(goal_update.id)).to eq(true)
    expect(goal_update.reload.checkin_id).to be_nil
  end
end
