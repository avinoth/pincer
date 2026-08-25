require "rails_helper"

RSpec.describe Ai::Agent::Tools::EditGoal do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:creator) { create(:user, organization: organization, provider_uid: "U_CREATOR") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) do
    create(:goal, organization: organization, creator: creator, owners: [ owner ], title: "Grow activation",
      start_date: "2026-08-01", end_date: "2026-09-01")
  end
  let(:user) { owner }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "applies the given fields via UpdateGoal and posts a refreshed GoalDisplay card" do
    expect(UpdateGoal).to receive(:call).with(
      goal: goal, attributes: { title: "Grow activation faster", end_date: "2026-09-30" }, publish: false
    ).and_call_original

    result = tool.execute(goal_id: goal.id, title: "Grow activation faster", end_date: "2026-09-30")

    goal.reload
    expect(goal.title).to eq("Grow activation faster")
    expect(goal.end_date).to eq(Date.parse("2026-09-30"))

    expect(result[:id]).to eq(goal.id)
    expect(result[:title]).to eq("Grow activation faster")
    expect(result[:changed_fields]).to contain_exactly(:title, :end_date)
    expect(result[:note]).to include("Edit button")

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      # GoalDisplay nests its blocks in a colored attachment now.
      expect(payload[:attachments].to_s).to include("Grow activation faster")
    end
  end

  it "only assigns the params that were actually provided" do
    original_description = goal.description

    tool.execute(goal_id: goal.id, title: "New title")

    goal.reload
    expect(goal.title).to eq("New title")
    expect(goal.description).to eq(original_description)
    expect(goal.start_date).to eq(Date.parse("2026-08-01"))
  end

  it "returns an error, without posting, when the goal isn't found in this organization" do
    other_org_goal = create(:goal)

    result = tool.execute(goal_id: other_org_goal.id, title: "Hijacked")

    expect(result).to eq(error: "No goal found with id #{other_org_goal.id}.")
    expect(send_message).not_to have_received(:send_message)
  end

  it "rejects edits from a user who is neither the creator nor an owner, and makes no change" do
    stranger = create(:user, organization: organization, provider_uid: "U_STRANGER")
    context_as_stranger = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: stranger, agent_run: nil
    )
    original_title = goal.title

    result = described_class.new(context_as_stranger).execute(goal_id: goal.id, title: "Hijacked title")

    expect(result).to eq(error: "Only the goal's owners or creator can edit it.")
    expect(goal.reload.title).to eq(original_title)
    expect(send_message).not_to have_received(:send_message)
  end

  it "allows the goal's creator (not just an owner) to edit it" do
    context_as_creator = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: creator, agent_run: nil
    )

    result = described_class.new(context_as_creator).execute(goal_id: goal.id, title: "Creator edit")

    expect(result[:title]).to eq("Creator edit")
  end

  it "returns the validation error and makes no change when the edit is invalid" do
    original_end_date = goal.end_date

    result = tool.execute(goal_id: goal.id, end_date: "2026-01-01")

    expect(result[:error]).to be_present
    expect(goal.reload.end_date).to eq(original_end_date)
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(goal_id: goal.id, title: "New title")

    expect(result).to eq(error: "Couldn't edit goal #{goal.id}: boom")
  end

  describe "update_channel" do
    it "accepts a bare Slack channel id and passes it through to UpdateGoal" do
      expect(UpdateGoal).to receive(:call).with(
        goal: goal, attributes: { update_channel: "C012AB34" }, publish: false
      ).and_call_original

      result = tool.execute(goal_id: goal.id, update_channel: "C012AB34")

      expect(goal.reload.update_channel).to eq("C012AB34")
      expect(result[:error]).to be_nil
    end

    it "normalizes a Slack channel mention token down to its captured id" do
      expect(UpdateGoal).to receive(:call).with(
        goal: goal, attributes: { update_channel: "C012AB" }, publish: false
      ).and_call_original

      result = tool.execute(goal_id: goal.id, update_channel: "<#C012AB|growth>")

      expect(goal.reload.update_channel).to eq("C012AB")
      expect(result[:error]).to be_nil
    end

    it "rejects a plain channel name, with no mutation and no UpdateGoal call" do
      expect(UpdateGoal).not_to receive(:call)
      original_channel = goal.update_channel

      result = tool.execute(goal_id: goal.id, update_channel: "growth")

      expect(result[:error]).to include("growth")
      expect(goal.reload.update_channel).to eq(original_channel)
      expect(send_message).not_to have_received(:send_message)
    end
  end
end
