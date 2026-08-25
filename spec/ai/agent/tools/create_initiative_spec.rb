require "rails_helper"

RSpec.describe Ai::Agent::Tools::CreateInitiative do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:requester) { create(:user, organization: organization, provider_uid: "U_REQUESTER") }
  let(:goal) { create(:goal, organization: organization, title: "Grow activation") }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: requester, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "creates the initiative and posts a fresh InitiativeDisplay card" do
    result = tool.execute(goal_id: goal.id, title: "Ship onboarding revamp", description: "desc")

    initiative = Initiative.sole
    expect(initiative.goal).to eq(goal)
    expect(initiative.title).to eq("Ship onboarding revamp")
    expect(initiative.description).to eq("desc")
    expect(initiative).to be_status_proposed

    expect(result[:id]).to eq(initiative.id)
    expect(result[:title]).to eq("Ship onboarding revamp")
    expect(result[:goal_id]).to eq(goal.id)

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:attachments].to_s).to include("Ship onboarding revamp")
    end
  end

  it "defaults the owner to the requesting user when none is given" do
    result = tool.execute(goal_id: goal.id, title: "Ship onboarding revamp")

    expect(Initiative.sole.owner).to eq(requester)
    expect(result[:owner]).to eq(requester.full_name)
  end

  it "resolves an explicit owner from a Slack user mention" do
    owner = create(:user, organization: organization, provider_uid: "U012OWNER")
    allow(CreateUserFromSlack).to receive(:call)
      .with(organization: organization, slack_user_id: "U012OWNER")
      .and_call_original

    tool.execute(goal_id: goal.id, title: "Ship onboarding revamp", owner: "<@U012OWNER>")

    expect(Initiative.sole.owner).to eq(owner)
  end

  it "returns an error, without creating anything, when the goal isn't found in this organization" do
    other_org_goal = create(:goal)

    result = tool.execute(goal_id: other_org_goal.id, title: "Hijacked")

    expect(result).to eq(error: "No goal found with id #{other_org_goal.id}.")
    expect(Initiative.count).to eq(0)
    expect(send_message).not_to have_received(:send_message)
  end

  it "rejects a goal in a terminal lifecycle state, without creating anything" do
    goal.update!(status: "completed")

    result = tool.execute(goal_id: goal.id, title: "Too late")

    expect(result[:error]).to include("completed")
    expect(Initiative.count).to eq(0)
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(goal_id: goal.id, title: "Ship onboarding revamp")

    expect(result).to eq(error: "Couldn't create the initiative: boom")
  end
end
