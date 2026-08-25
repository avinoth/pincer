require "rails_helper"

RSpec.describe Ai::Agent::Tools::UpdateInitiativeStatus do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:goal_owner) { create(:user, organization: organization, provider_uid: "U_GOAL_OWNER") }
  let(:goal) { create(:goal, organization: organization, owners: [ goal_owner ], title: "Grow activation") }
  let!(:metric) { create(:metric, goal: goal) }
  let(:initiative_owner) { create(:user, organization: organization, provider_uid: "U_INITIATIVE_OWNER") }
  let(:initiative) { create(:initiative, goal: goal, owner: initiative_owner, title: "Ship onboarding", status: "in_progress") }
  let(:user) { initiative_owner }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "updates the initiative's status, logs a GoalUpdate, and posts a refreshed card" do
    result = tool.execute(initiative_id: initiative.id, status: "done")

    expect(initiative.reload).to be_status_done
    expect(GoalUpdate.sole).to be_kind_initiative_status

    expect(result[:initiative_id]).to eq(initiative.id)
    expect(result[:status]).to eq("done")

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:attachments].to_s).to include("Grow activation")
    end
  end

  it "links the GoalUpdate to an open checkin when checkin_id is given" do
    checkin = create(:checkin, organization: organization, user: initiative_owner, goal: goal, initiative: initiative)

    tool.execute(initiative_id: initiative.id, status: "done", checkin_id: checkin.id)

    expect(GoalUpdate.sole.checkin).to eq(checkin)
  end

  it "returns an error, without posting, when the initiative isn't found in this organization" do
    other_org_initiative = create(:initiative)

    result = tool.execute(initiative_id: other_org_initiative.id, status: "done")

    expect(result).to eq(error: "No initiative found with id #{other_org_initiative.id}.")
    expect(send_message).not_to have_received(:send_message)
  end

  it "allows the parent goal's owner (not just the initiative's own owner) to update it" do
    context_as_goal_owner = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: goal_owner, agent_run: nil
    )

    result = described_class.new(context_as_goal_owner).execute(initiative_id: initiative.id, status: "done")

    expect(result[:status]).to eq("done")
  end

  it "rejects an update from an unrelated user" do
    stranger = create(:user, organization: organization, provider_uid: "U_STRANGER")
    context_as_stranger = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: stranger, agent_run: nil
    )

    result = described_class.new(context_as_stranger).execute(initiative_id: initiative.id, status: "done")

    expect(result).to eq(error: "Only the initiative's owner or the goal's owners/creator can update it.")
    expect(initiative.reload).to be_status_in_progress
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns the validation error and makes no change for an invalid status" do
    result = tool.execute(initiative_id: initiative.id, status: "not_a_real_status")

    expect(result[:error]).to be_present
    expect(initiative.reload).to be_status_in_progress
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(initiative_id: initiative.id, status: "done")

    expect(result).to eq(error: "Couldn't update initiative #{initiative.id}: boom")
  end
end
