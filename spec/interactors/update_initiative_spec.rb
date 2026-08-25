require "rails_helper"

RSpec.describe UpdateInitiative do
  let(:organization) { create(:organization) }

  def call(initiative, attributes: {})
    described_class.call(initiative: initiative, attributes: attributes)
  end

  it "updates the given attributes" do
    initiative = create(:initiative, title: "Old title")

    result = call(initiative, attributes: { title: "New title", description: "New desc" })

    expect(result).to be_success
    initiative.reload
    expect(initiative.title).to eq("New title")
    expect(initiative.description).to eq("New desc")
  end

  it "reassigns the owner when given" do
    initiative = create(:initiative)
    new_owner = create(:user, organization: initiative.goal.organization)

    result = call(initiative, attributes: { owner: new_owner })

    expect(result).to be_success
    expect(initiative.reload.owner).to eq(new_owner)
  end

  it "unassigns the owner when given nil" do
    owner = create(:user)
    initiative = create(:initiative, owner: owner)

    result = call(initiative, attributes: { owner: nil })

    expect(result).to be_success
    expect(initiative.reload.owner).to be_nil
  end

  it "changes the status" do
    initiative = create(:initiative, status: "proposed")

    result = call(initiative, attributes: { status: "in_progress" })

    expect(result).to be_success
    expect(initiative.reload).to be_status_in_progress
  end

  it "never reassigns the parent goal" do
    goal = create(:goal)
    initiative = create(:initiative, goal: goal)
    other_goal = create(:goal, organization: goal.organization)

    call(initiative, attributes: { title: "Updated", goal: other_goal })

    expect(initiative.reload.goal).to eq(goal)
  end

  it "fails on invalid attributes" do
    initiative = create(:initiative)

    result = call(initiative, attributes: { title: nil })

    expect(result).to be_failure
    expect(initiative.reload.title).not_to be_nil
  end
end
