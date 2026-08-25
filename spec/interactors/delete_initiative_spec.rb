require "rails_helper"

RSpec.describe DeleteInitiative do
  let(:organization) { create(:organization) }
  let(:goal) { create(:goal, organization: organization, title: "Grow activation") }
  let(:initiative) { create(:initiative, goal: goal, title: "Ship onboarding revamp") }

  def call(overrides = {})
    described_class.call({ initiative: initiative }.merge(overrides))
  end

  it "destroys the initiative" do
    result = call

    expect(result).to be_success
    expect { initiative.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "captures the title and parent goal title before destroying" do
    result = call

    expect(result.deleted_title).to eq("Ship onboarding revamp")
    expect(result.goal_title).to eq("Grow activation")
  end

  it "cascades to dependent checkins and goal_updates" do
    checkin = create(:checkin, organization: organization, goal: goal, initiative: initiative, user: create(:user, organization: organization))
    goal_update = create(:goal_update, goal: goal, initiative: initiative)

    call

    expect(Checkin.exists?(checkin.id)).to be false
    expect(GoalUpdate.exists?(goal_update.id)).to be false
  end

  it "fails and notifies Bugsnag when the destroy raises" do
    allow(initiative).to receive(:destroy!).and_raise(StandardError, "boom")
    expect(Bugsnag).to receive(:notify)

    result = call

    expect(result).to be_failure
    expect(result.error).to eq("boom")
  end
end
