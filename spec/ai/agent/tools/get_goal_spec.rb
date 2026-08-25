require "rails_helper"

RSpec.describe Ai::Agent::Tools::GetGoal do
  let(:organization) { create(:organization) }
  let(:conversation) { create(:conversation, organization: organization) }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  it "returns full detail including initiatives with owner names or \"unassigned\"" do
    owner = create(:user, organization: organization, full_name: "Ada Lovelace")
    goal = create(:goal, organization: organization, title: "Grow activation", description: "Ship the funnel work",
      owners: [ owner ])
    create(:metric, goal: goal, name: "Activation rate", start_value: 20, current_value: 25, target_value: 40,
      unit: "%", direction: "increase")
    assigned = create(:initiative, goal: goal, title: "Ship onboarding revamp", owner: owner)
    unassigned = create(:initiative, goal: goal, title: "Audit funnel drop-off", owner: nil)

    result = tool.execute(goal_id: goal.id)

    expect(result[:id]).to eq(goal.id)
    expect(result[:title]).to eq("Grow activation")
    expect(result[:description]).to eq("Ship the funnel work")
    expect(result[:owners]).to eq([ "Ada Lovelace" ])
    expect(result[:metric]).to eq(name: "Activation rate", start: BigDecimal("20"), current: BigDecimal("25"),
      target: BigDecimal("40"), unit: "%", direction: "increase")

    initiative_titles = result[:initiatives].map { |i| i[:title] }
    expect(initiative_titles).to contain_exactly(assigned.title, unassigned.title)
    expect(result[:initiatives].find { |i| i[:title] == assigned.title }[:owner]).to eq("Ada Lovelace")
    expect(result[:initiatives].find { |i| i[:title] == unassigned.title }[:owner]).to eq("unassigned")
  end

  it "includes children and parent" do
    parent = create(:goal, organization: organization, title: "North Star")
    goal = create(:goal, organization: organization, parent: parent)
    child = create(:goal, organization: organization, parent: goal)

    result = tool.execute(goal_id: goal.id)

    expect(result[:parent]).to eq(id: parent.id, title: "North Star")
    expect(result[:children]).to eq([ { id: child.id, title: child.title, status: child.status } ])
  end

  it "returns an error string, not an exception, when the goal isn't found in this organization" do
    other_org_goal = create(:goal)

    result = tool.execute(goal_id: other_org_goal.id)

    expect(result).to eq(error: "No goal found with id #{other_org_goal.id}.")
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(goal_id: 1)

    expect(result).to eq(error: "Couldn't load goal 1: boom")
  end
end
