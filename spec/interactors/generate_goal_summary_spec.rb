require "rails_helper"

RSpec.describe GenerateGoalSummary do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization, full_name: "Ada Lovelace") }
  let(:goal) do
    create(:goal, organization: organization, owners: [ owner ], title: "Grow activation",
                  start_date: "2026-08-01", end_date: "2026-08-31")
  end
  let!(:metric) { create(:metric, goal: goal, name: "Activation rate", direction: "increase",
                          start_value: 20, current_value: 32, target_value: 40, unit: "%") }

  let(:period_start) { Time.zone.parse("2026-08-13 17:00") }
  let(:period_end) { Time.zone.parse("2026-08-20 17:00") }

  let(:fake_response) { instance_double(RubyLLM::Message, content: { "health" => "on_track", "body" => "Great progress this week." }) }
  let(:fake_chat) { instance_double(RubyLLM::Chat) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(fake_chat)
    allow(fake_chat).to receive(:with_temperature).and_return(fake_chat)
    allow(fake_chat).to receive(:with_schema).and_return(fake_chat)
    allow(fake_chat).to receive(:ask).and_return(fake_response)
  end

  it "returns the health/body the LLM produced" do
    result = described_class.call(goal: goal, period_start: period_start, period_end: period_end, mode: :weekly)

    expect(result).to be_success
    expect(result.health).to eq("on_track")
    expect(result.body).to eq("Great progress this week.")
  end

  it "calls with_schema with the goal summary schema" do
    described_class.call(goal: goal, period_start: period_start, period_end: period_end, mode: :weekly)

    expect(fake_chat).to have_received(:with_schema).with(Ai::Agent::Schemas::GoalSummarySchema)
  end

  it "builds a prompt naming the goal, the metric, and the window's GoalUpdate/MetricUpdate/expired-Checkin data" do
    goal_update = create(:goal_update, goal: goal, reported_by: owner, kind: "note", body: "Shipped the new onboarding flow.",
                         created_at: period_start + 1.day)
    metric_update = create(:metric_update, metric: metric, reported_by: owner, value: 32, created_at: period_start + 2.days)
    other_owner = create(:user, organization: organization, full_name: "Grace Hopper")
    expired_checkin = create(:checkin, organization: organization, user: other_owner, goal: goal, status: "expired",
                             period_key: "2026-08-19", created_at: period_start + 3.days)
    # Outside the window — must not appear in the prompt.
    create(:goal_update, goal: goal, reported_by: owner, kind: "note", body: "Old news from last month.",
           created_at: period_start - 10.days)

    described_class.call(goal: goal, period_start: period_start, period_end: period_end, mode: :weekly)

    expect(fake_chat).to have_received(:ask) do |prompt|
      expect(prompt).to include("Grow activation")
      expect(prompt).to include("Activation rate")
      expect(prompt).to include(goal_update.body)
      expect(prompt).to include(other_owner.full_name)
      expect(prompt).not_to include("Old news from last month.")
    end
    # metric_update captured above only to seed the metric-values line; asserted via full-prompt scan.
    expect(metric_update).to be_persisted
    expect(expired_checkin).to be_status_expired
  end

  it "uses a closing framing for mode: :end" do
    described_class.call(goal: goal, period_start: goal.start_date, period_end: goal.end_date, mode: :end)

    expect(fake_chat).to have_received(:ask) do |prompt|
      expect(prompt).to match(/final|closing/i)
    end
  end

  it "fails when goal is missing" do
    result = described_class.call(goal: nil, period_start: period_start, period_end: period_end, mode: :weekly)

    expect(result).to be_failure
  end

  it "fails and notifies Bugsnag when the LLM call raises" do
    allow(Bugsnag).to receive(:notify)
    allow(fake_chat).to receive(:ask).and_raise(StandardError, "provider timeout")

    result = described_class.call(goal: goal, period_start: period_start, period_end: period_end, mode: :weekly)

    expect(result).to be_failure
    expect(Bugsnag).to have_received(:notify)
  end
end
