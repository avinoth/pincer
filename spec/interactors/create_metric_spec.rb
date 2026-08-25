require "rails_helper"

RSpec.describe CreateMetric do
  let(:goal) { create(:goal) }

  it "creates the metric and seeds current_value to the baseline" do
    result = CreateMetric.call(
      goal: goal, name: "Activation rate", direction: "increase",
      start_value: "20", target_value: "40", unit: "%"
    )

    expect(result).to be_success
    metric = result.metric
    expect(metric.current_value).to eq(metric.start_value)
    expect(metric.current_value).to eq(20)
    expect(goal.reload.metric).to eq(metric)
  end

  it "defaults a blank start_value to zero" do
    result = CreateMetric.call(
      goal: goal, name: "Signups", direction: "increase", start_value: nil, target_value: "1000"
    )

    expect(result.metric.start_value).to eq(0)
    expect(result.metric.current_value).to eq(0)
  end

  it "fails cleanly when the goal already has a metric" do
    create(:metric, goal: goal)

    result = CreateMetric.call(goal: goal, name: "Dup", direction: "increase", target_value: "9")

    expect(result).to be_failure
    expect(goal.reload.metric.name).not_to eq("Dup")
  end
end
