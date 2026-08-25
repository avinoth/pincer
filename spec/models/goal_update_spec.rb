require "rails_helper"

RSpec.describe GoalUpdate do
  it { is_expected.to belong_to(:checkin).optional }
  it { is_expected.to belong_to(:goal) }
  it { is_expected.to belong_to(:initiative).optional }
  it { is_expected.to belong_to(:reported_by).class_name("User").optional }
  it { is_expected.to belong_to(:metric_update).optional }

  it { is_expected.to validate_presence_of(:kind) }

  it do
    is_expected.to define_enum_for(:kind)
      .with_values(metric: "metric", initiative_status: "initiative_status", note: "note")
      .backed_by_column_of_type(:string)
      .with_prefix("kind")
  end

  it "is readable through the goal, and through the metric_update it narrates" do
    goal = create(:goal)
    metric = create(:metric, goal: goal)
    reporter = create(:user, organization: goal.organization)
    metric_update = create(:metric_update, metric: metric, reported_by: reporter)
    goal_update = GoalUpdate.create!(goal: goal, reported_by: reporter, kind: :metric, metric_update: metric_update)

    expect(goal.goal_updates).to include(goal_update)
    expect(metric_update.goal_update).to eq(goal_update)
  end

  it "allows checkin_id and metric_update_id to be nil (ad-hoc updates)" do
    goal_update = create(:goal_update, kind: "note", checkin: nil)
    expect(goal_update).to be_valid
    expect(goal_update.checkin_id).to be_nil
    expect(goal_update.metric_update_id).to be_nil
  end
end
