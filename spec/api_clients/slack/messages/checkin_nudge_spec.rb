require "rails_helper"

RSpec.describe Slack::Messages::CheckinNudge do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization) }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ], title: "Grow activation") }
  let!(:metric) { create(:metric, goal: goal, name: "Activation rate", current_value: 20, target_value: 40, unit: "%") }

  it "builds a header, one CTA, and a text fallback naming the goal(s)" do
    checkin = create(:checkin, organization: organization, user: owner, goal: goal, period_key: "2026-08-20")

    payload = described_class.new(checkins: [ checkin ]).to_h

    expect(payload[:text]).to include("Grow activation")
    expect(payload[:blocks].first[:type]).to eq("section")
    expect(payload[:blocks].to_s).to include("check-in")
    expect(payload[:blocks].to_s).to include("Reply here to check in")
  end

  it "renders the metric line for a metric-subject checkin (initiative_id nil)" do
    checkin = create(:checkin, organization: organization, user: owner, goal: goal, period_key: "2026-08-20")

    payload = described_class.new(checkins: [ checkin ]).to_h

    expect(payload[:blocks].to_s).to include("Activation rate").and include("20%").and include("40%")
  end

  it "renders an initiative line, without the metric line, for an initiative-subject checkin" do
    initiative = create(:initiative, goal: goal, title: "Ship onboarding", status: "in_progress")
    checkin = create(:checkin, organization: organization, user: owner, goal: goal, initiative: initiative,
                     period_key: "2026-08-20")

    payload = described_class.new(checkins: [ checkin ]).to_h

    expect(payload[:blocks].to_s).to include("Ship onboarding").and include("in_progress")
    expect(payload[:blocks].to_s).not_to include("Activation rate")
  end

  it "clubs both a metric checkin and an initiative checkin under one goal section" do
    initiative = create(:initiative, goal: goal, title: "Ship onboarding")
    metric_checkin = create(:checkin, organization: organization, user: owner, goal: goal, period_key: "2026-08-20")
    initiative_checkin = create(:checkin, organization: organization, user: owner, goal: goal, initiative: initiative,
                                period_key: "2026-08-20")

    payload = described_class.new(checkins: [ metric_checkin, initiative_checkin ]).to_h

    goal_blocks = payload[:blocks].select { |b| b[:type] == "section" }
    combined = goal_blocks.to_s
    expect(combined).to include("Grow activation").and include("Activation rate").and include("Ship onboarding")
  end

  it "renders one section per distinct goal across multiple goals" do
    other_goal = create(:goal, organization: organization, owners: [ owner ], title: "Reduce churn")
    checkin_a = create(:checkin, organization: organization, user: owner, goal: goal, period_key: "2026-08-20")
    checkin_b = create(:checkin, organization: organization, user: owner, goal: other_goal, period_key: "2026-08-20")

    payload = described_class.new(checkins: [ checkin_a, checkin_b ]).to_h

    expect(payload[:text]).to include("Grow activation").and include("Reduce churn")
    expect(payload[:blocks].to_s).to include("Grow activation").and include("Reduce churn")
  end
end
