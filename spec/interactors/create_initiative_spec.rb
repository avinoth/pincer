require "rails_helper"

RSpec.describe CreateInitiative do
  let(:organization) { create(:organization) }
  let(:goal) { create(:goal, organization: organization) }
  let(:creator) { create(:user, organization: organization) }
  let(:owner) { create(:user, organization: organization) }

  def call(overrides = {})
    described_class.call({
      goal: goal,
      creator: creator,
      owner: owner,
      title: "Ship onboarding revamp",
      description: "desc"
    }.merge(overrides))
  end

  it "creates the initiative under the goal" do
    result = call

    expect(result).to be_success
    initiative = result.initiative
    expect(initiative).to be_persisted
    expect(initiative.goal).to eq(goal)
    expect(initiative.creator).to eq(creator)
    expect(initiative.owner).to eq(owner)
    expect(initiative.title).to eq("Ship onboarding revamp")
    expect(initiative.description).to eq("desc")
    expect(initiative).to be_status_proposed
  end

  it "allows a nil owner (unassigned initiative)" do
    result = call(owner: nil)

    expect(result).to be_success
    expect(result.initiative.owner).to be_nil
  end

  it "allows a nil creator" do
    result = call(creator: nil)

    expect(result).to be_success
    expect(result.initiative.creator).to be_nil
  end

  it "fails and creates nothing when the goal doesn't accept new initiatives" do
    goal.update!(status: "completed")

    expect { @result = call }.not_to change(Initiative, :count)

    expect(@result).to be_failure
    expect(@result.error).to include("completed")
  end

  it "fails and creates nothing when the goal has ended" do
    goal.update!(status: "ended")

    expect { @result = call }.not_to change(Initiative, :count)

    expect(@result).to be_failure
  end

  it "fails and rolls back on invalid data" do
    expect { @result = call(title: nil) }.not_to change(Initiative, :count)

    expect(@result).to be_failure
  end
end
