require "rails_helper"

RSpec.describe UpdateMetric do
  let(:metric) { create(:metric, name: "Old name", direction: "increase", start_value: 20, target_value: 40) }

  it "updates the metric and re-seeds current_value from the new start_value" do
    result = UpdateMetric.call(
      metric: metric, name: "New name", direction: "decrease", start_value: "30", target_value: "10", unit: "days"
    )

    expect(result).to be_success
    metric.reload
    expect(metric.name).to eq("New name")
    expect(metric.direction).to eq("decrease")
    expect(metric.start_value).to eq(30)
    expect(metric.current_value).to eq(30)
    expect(metric.target_value).to eq(10)
    expect(metric.unit).to eq("days")
  end

  it "defaults a blank start_value to zero" do
    result = UpdateMetric.call(metric: metric, name: "Signups", direction: "increase", start_value: nil, target_value: "1000")

    expect(result.metric.start_value).to eq(0)
    expect(result.metric.current_value).to eq(0)
  end

  it "fails cleanly and leaves the metric untouched when the update is invalid" do
    result = UpdateMetric.call(metric: metric, name: "", direction: "increase", target_value: "40")

    expect(result).to be_failure
    expect(metric.reload.name).to eq("Old name")
  end
end
