require "rails_helper"

RSpec.describe Slack::Interactions::DeleteInitiativeAction do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }

  def payload(initiative, user_id:)
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "channel" => { "id" => "C_CARD" },
      "container" => { "message_ts" => "111.222" },
      "actions" => [
        { "action_id" => "delete_initiative", "value" => initiative.id.to_s }
      ]
    }
  end

  before do
    allow(Slack::Request::UpdateMessage).to receive(:new).and_return(
      instance_double(Slack::Request::UpdateMessage, update_message: nil)
    )
  end

  it "deletes the initiative and replaces the card with a tombstone when the owner clicks Delete" do
    goal = create(:goal, organization: organization)
    owner = create(:user, organization: organization, provider_uid: "U_OWNER")
    initiative = create(:initiative, goal: goal, owner: owner, title: "Ship onboarding revamp")

    updater = instance_double(Slack::Request::UpdateMessage)
    allow(Slack::Request::UpdateMessage).to receive(:new).with(workspace).and_return(updater)
    expect(updater).to receive(:update_message) do |channel, ts, message|
      expect(channel).to eq("C_CARD")
      expect(ts).to eq("111.222")
      expect(message[:text]).to eq("🗑️ Initiative *Ship onboarding revamp* deleted.")
    end

    result = described_class.new(payload(initiative, user_id: "U_OWNER")).call

    expect(result).to be_nil
    expect(Initiative.exists?(initiative.id)).to be false
  end

  it "allows the goal's creator (not just the initiative's owner) to delete it" do
    creator = create(:user, organization: organization, provider_uid: "U_CREATOR")
    goal = create(:goal, organization: organization, creator: creator)
    initiative = create(:initiative, goal: goal, title: "Ship onboarding revamp")

    described_class.new(payload(initiative, user_id: "U_CREATOR")).call

    expect(Initiative.exists?(initiative.id)).to be false
  end

  it "refuses an unauthorized clicker with an ephemeral message and does not delete" do
    goal = create(:goal, organization: organization)
    owner = create(:user, organization: organization, provider_uid: "U_OWNER")
    initiative = create(:initiative, goal: goal, owner: owner, title: "Ship onboarding revamp")

    sender = instance_double(Slack::Request::SendMessage, send_ephemeral: nil)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    expect(sender).to receive(:send_ephemeral).with(
      "C_CARD", "U_STRANGER", { text: "Only the initiative's owner or the goal's owners/creator can delete it." }
    )

    result = described_class.new(payload(initiative, user_id: "U_STRANGER")).call

    expect(result).to be_nil
    expect(Initiative.exists?(initiative.id)).to be true
    expect(Slack::Request::UpdateMessage).not_to have_received(:new)
  end

  it "does nothing when the initiative doesn't exist in this organization" do
    foreign_initiative = create(:initiative)

    result = described_class.new(payload(foreign_initiative, user_id: "U_ANYONE")).call

    expect(result).to be_nil
    expect(Initiative.exists?(foreign_initiative.id)).to be true
    expect(Slack::Request::UpdateMessage).not_to have_received(:new)
  end
end
