require "rails_helper"

RSpec.describe Ai::Agent::Tools::EditInitiative do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:goal_creator) { create(:user, organization: organization, provider_uid: "U_CREATOR") }
  let(:goal) { create(:goal, organization: organization, creator: goal_creator) }
  let(:initiative_owner) { create(:user, organization: organization, provider_uid: "U_INIT_OWNER") }
  let(:initiative) do
    create(:initiative, goal: goal, owner: initiative_owner, title: "Ship onboarding revamp", status: "proposed")
  end
  let(:user) { initiative_owner }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "applies the given fields via UpdateInitiative and posts a refreshed InitiativeDisplay card" do
    expect(UpdateInitiative).to receive(:call).with(
      initiative: initiative, attributes: { title: "Ship onboarding revamp v2", status: "in_progress" }
    ).and_call_original

    result = tool.execute(initiative_id: initiative.id, title: "Ship onboarding revamp v2", status: "in_progress")

    initiative.reload
    expect(initiative.title).to eq("Ship onboarding revamp v2")
    expect(initiative).to be_status_in_progress

    expect(result[:id]).to eq(initiative.id)
    expect(result[:title]).to eq("Ship onboarding revamp v2")
    expect(result[:changed_fields]).to contain_exactly(:title, :status)

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:attachments].to_s).to include("Ship onboarding revamp v2")
    end
  end

  it "only assigns the params that were actually provided" do
    original_description = initiative.description

    tool.execute(initiative_id: initiative.id, title: "New title")

    initiative.reload
    expect(initiative.title).to eq("New title")
    expect(initiative.description).to eq(original_description)
  end

  it "resolves a new owner from a Slack user mention" do
    new_owner = create(:user, organization: organization, provider_uid: "U012NEWOWNER")

    result = tool.execute(initiative_id: initiative.id, owner: "<@U012NEWOWNER>")

    expect(initiative.reload.owner).to eq(new_owner)
    expect(result[:owner]).to eq(new_owner.full_name)
  end

  it "returns an error, without posting, when the initiative isn't found in this organization" do
    other_org_initiative = create(:initiative)

    result = tool.execute(initiative_id: other_org_initiative.id, title: "Hijacked")

    expect(result).to eq(error: "No initiative found with id #{other_org_initiative.id}.")
    expect(send_message).not_to have_received(:send_message)
  end

  it "rejects edits from a user unrelated to the initiative or its goal, and makes no change" do
    stranger = create(:user, organization: organization, provider_uid: "U_STRANGER")
    context_as_stranger = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: stranger, agent_run: nil
    )
    original_title = initiative.title

    result = described_class.new(context_as_stranger).execute(initiative_id: initiative.id, title: "Hijacked title")

    expect(result).to eq(error: "Only the initiative's owner or the goal's owners/creator can edit it.")
    expect(initiative.reload.title).to eq(original_title)
    expect(send_message).not_to have_received(:send_message)
  end

  it "allows the goal's creator (not just the initiative's owner) to edit it" do
    context_as_creator = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: goal_creator, agent_run: nil
    )

    result = described_class.new(context_as_creator).execute(initiative_id: initiative.id, title: "Creator edit")

    expect(result[:title]).to eq("Creator edit")
  end

  it "returns the validation error and makes no change when the edit is invalid" do
    original_title = initiative.title

    result = tool.execute(initiative_id: initiative.id, title: "")

    expect(result[:error]).to be_present
    expect(initiative.reload.title).to eq(original_title)
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(UpdateInitiative).to receive(:call).and_raise(StandardError, "boom")

    result = tool.execute(initiative_id: initiative.id, title: "New title")

    expect(result).to eq(error: "Couldn't edit initiative #{initiative.id}: boom")
  end

  describe "owner" do
    it "rejects an owner value that doesn't look like a Slack user id, with no mutation" do
      expect(UpdateInitiative).not_to receive(:call)
      original_owner = initiative.owner

      result = tool.execute(initiative_id: initiative.id, owner: "not a mention")

      expect(result[:error]).to include("not a mention")
      expect(initiative.reload.owner).to eq(original_owner)
      expect(send_message).not_to have_received(:send_message)
    end
  end
end
