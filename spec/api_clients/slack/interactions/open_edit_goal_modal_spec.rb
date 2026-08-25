require "rails_helper"

RSpec.describe Slack::Interactions::OpenEditGoalModal do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:goal) { create(:goal, organization: organization, title: "Grow activation") }

  let(:open_view) { instance_double(Slack::Request::OpenView, open_modal: nil) }

  before { allow(Slack::Request::OpenView).to receive(:new).and_return(open_view) }

  def payload(value:, user_id: "U1")
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "channel" => { "id" => "C1" },
      "trigger_id" => "trigger-123",
      "container" => { "message_ts" => "111.222" },
      "actions" => [ { "action_id" => "edit_goal", "value" => value } ]
    }
  end

  it "opens a prefilled Edit Goal modal with the click's trigger_id and origin card for the creator" do
    described_class.new(payload(value: goal.id.to_s, user_id: goal.creator.provider_uid)).call

    expect(open_view).to have_received(:open_modal) do |view, trigger_id|
      expect(trigger_id).to eq("trigger-123")
      expect(view).to be_a(Slack::Views::EditGoalModal)

      metadata = JSON.parse(view.private_metadata)
      expect(metadata).to eq("goal_id" => goal.id, "channel" => "C1", "message_ts" => "111.222")
    end
  end

  it "opens the modal for a goal owner" do
    owner = create(:user, organization: organization)
    goal.owners = [ owner ]

    described_class.new(payload(value: goal.id.to_s, user_id: owner.provider_uid)).call

    expect(open_view).to have_received(:open_modal)
  end

  it "does nothing when the referenced goal is missing" do
    described_class.new(payload(value: "0")).call
    expect(open_view).not_to have_received(:open_modal)
  end

  it "sends an ephemeral denial and does not open the modal for an unauthorized user" do
    sender = instance_double(Slack::Request::SendMessage)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    expect(sender).to receive(:send_ephemeral) do |channel, user, message|
      expect(channel).to eq("C1")
      expect(user).to eq("U_UNRELATED")
      expect(message[:text]).to match(/creator or an owner/)
    end

    described_class.new(payload(value: goal.id.to_s, user_id: "U_UNRELATED")).call

    expect(open_view).not_to have_received(:open_modal)
  end
end
