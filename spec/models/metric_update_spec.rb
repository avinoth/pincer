require "rails_helper"

RSpec.describe MetricUpdate do
  it { is_expected.to belong_to(:reported_by).class_name("User").optional }

  it "requires a value and a metric, but not a reporter" do
    update = MetricUpdate.new
    expect(update).not_to be_valid
    expect(update.errors.attribute_names).to include(:value, :metric)
    expect(update.errors.attribute_names).not_to include(:reported_by)
  end

  it "attributes the value to its reporter" do
    metric = create(:metric)
    user = create(:user, organization: metric.goal.organization)
    update = metric.metric_updates.create!(reported_by: user, value: "25", note: "wk1")

    expect(update.reported_by).to eq(user)
  end
end
