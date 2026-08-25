require "rails_helper"

RSpec.describe Ai::Agent::Tools::AddGoalUpdate do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:goal_owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) { create(:goal, organization: organization, owners: [ goal_owner ], title: "Grow activation") }
  let!(:metric) { create(:metric, goal: goal) }
  let(:user) { goal_owner }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "logs a free-text GoalUpdate and posts a refreshed card" do
    result = tool.execute(goal_id: goal.id, body: "Kickoff went well.")

    goal_update = GoalUpdate.sole
    expect(goal_update).to be_kind_note
    expect(goal_update.body).to eq("Kickoff went well.")
    expect(goal_update.initiative).to be_nil

    expect(result[:goal_update_id]).to eq(goal_update.id)

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:attachments].to_s).to include("Grow activation")
    end
  end

  it "scopes the note to an initiative, and links it to an open checkin, when given" do
    initiative = create(:initiative, goal: goal, title: "Ship onboarding")
    checkin = create(:checkin, organization: organization, user: goal_owner, goal: goal, initiative: initiative)

    tool.execute(goal_id: goal.id, body: "On track", initiative_id: initiative.id, checkin_id: checkin.id)

    goal_update = GoalUpdate.sole
    expect(goal_update.initiative).to eq(initiative)
    expect(goal_update.checkin).to eq(checkin)
  end

  it "returns an error, without posting, when the goal isn't found in this organization" do
    other_org_goal = create(:goal)

    result = tool.execute(goal_id: other_org_goal.id, body: "Hijacked")

    expect(result).to eq(error: "No goal found with id #{other_org_goal.id}.")
    expect(send_message).not_to have_received(:send_message)
    expect(GoalUpdate.count).to eq(0)
  end

  it "returns an error when initiative_id doesn't belong to that goal" do
    other_goal_initiative = create(:initiative)

    result = tool.execute(goal_id: goal.id, body: "note", initiative_id: other_goal_initiative.id)

    expect(result[:error]).to include("No initiative found")
    expect(GoalUpdate.count).to eq(0)
  end

  it "allows an initiative owner (not just the goal's owner/creator) to add a note" do
    initiative_owner = create(:user, organization: organization, provider_uid: "U_INIT_OWNER")
    create(:initiative, goal: goal, owner: initiative_owner)
    context_as_initiative_owner = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: initiative_owner, agent_run: nil
    )

    result = described_class.new(context_as_initiative_owner).execute(goal_id: goal.id, body: "progress note")

    expect(result[:error]).to be_nil
    expect(GoalUpdate.sole.reported_by).to eq(initiative_owner)
  end

  it "rejects a note from an unrelated user" do
    stranger = create(:user, organization: organization, provider_uid: "U_STRANGER")
    context_as_stranger = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: stranger, agent_run: nil
    )

    result = described_class.new(context_as_stranger).execute(goal_id: goal.id, body: "Hijacked")

    expect(result[:error]).to be_present
    expect(GoalUpdate.count).to eq(0)
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(goal_id: goal.id, body: "note")

    expect(result).to eq(error: "Couldn't add a note to goal #{goal.id}: boom")
  end
end
