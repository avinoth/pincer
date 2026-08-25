require "rails_helper"

RSpec.describe RecordMetricUpdate do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization) }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ]) }
  let(:metric) { create(:metric, goal: goal, start_value: 20, current_value: 20, target_value: 40, unit: "%") }

  def call(**overrides)
    described_class.call({ metric: metric, value: 30, reported_by: owner }.merge(overrides))
  end

  it "inserts a MetricUpdate, advances current_value, and logs a GoalUpdate(kind: metric)" do
    result = call

    expect(result).to be_success
    metric_update = result.metric_update
    expect(metric_update).to be_a(MetricUpdate)
    expect(metric_update.value).to eq(30)
    expect(metric_update.reported_by).to eq(owner)

    expect(metric.reload.current_value).to eq(30)

    goal_update = result.goal_update
    expect(goal_update).to be_kind_metric
    expect(goal_update.goal).to eq(goal)
    expect(goal_update.metric_update).to eq(metric_update)
    expect(goal_update.reported_by).to eq(owner)
    expect(goal_update.body).to include("30%")
  end

  it "links the GoalUpdate to the given checkin and folds a note into the body" do
    checkin = create(:checkin, organization: organization, user: owner, goal: goal)

    result = call(checkin: checkin, note: "hit a milestone")

    expect(result.goal_update.checkin).to eq(checkin)
    expect(result.goal_update.body).to include("hit a milestone")
    expect(result.metric_update.note).to eq("hit a milestone")
  end

  it "fails, without writing anything, when the reporter can't modify the goal" do
    stranger = create(:user, organization: organization)

    result = call(reported_by: stranger)

    expect(result).to be_failure
    expect(result.error).to be_present
    expect(metric.reload.current_value).to eq(20)
    expect(MetricUpdate.count).to eq(0)
    expect(GoalUpdate.count).to eq(0)
  end

  it "fails cleanly (never raises) on an invalid value" do
    expect {
      result = call(value: nil)
      expect(result).to be_failure
    }.not_to raise_error

    expect(metric.reload.current_value).to eq(20)
    expect(MetricUpdate.count).to eq(0)
  end
end
