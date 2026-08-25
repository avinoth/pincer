require "rails_helper"

RSpec.describe Slack::Interactions::EditInitiativeSubmission do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }

  def payload(initiative, values_overrides = {}, user_id: initiative.goal.creator.provider_uid,
              metadata: { "initiative_id" => initiative.id })
    values = {
      "title_block" => { "title" => { "value" => "Ship onboarding revamp v2" } },
      "description_block" => { "description" => { "value" => "desc" } },
      "owner_block" => { "owner" => { "selected_user" => owner.provider_uid } },
      "status_block" => { "status" => { "selected_option" => { "value" => "in_progress" } } }
    }.deep_merge(values_overrides)

    {
      "type" => "view_submission",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "view" => {
        "callback_id" => "edit_initiative",
        "private_metadata" => metadata.to_json,
        "state" => { "values" => values }
      }
    }
  end

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(
      instance_double(Slack::Request::SendMessage, send_message: nil)
    )
  end

  it "updates title, description, owner, and status" do
    goal = create(:goal, organization: organization)
    initiative = create(:initiative, goal: goal, title: "Old title", status: "proposed")

    result = described_class.new(payload(initiative)).call

    expect(result).to eq(response_action: "clear")
    initiative.reload
    expect(initiative.title).to eq("Ship onboarding revamp v2")
    expect(initiative.description).to eq("desc")
    expect(initiative.owner).to eq(owner)
    expect(initiative).to be_status_in_progress
  end

  it "unassigns the owner when no owner is selected" do
    goal = create(:goal, organization: organization)
    existing_owner = create(:user, organization: organization)
    initiative = create(:initiative, goal: goal, owner: existing_owner)

    result = described_class.new(
      payload(initiative, { "owner_block" => { "owner" => { "selected_user" => nil } } })
    ).call

    expect(result).to eq(response_action: "clear")
    expect(initiative.reload.owner).to be_nil
  end

  it "never reassigns the parent goal" do
    goal = create(:goal, organization: organization)
    initiative = create(:initiative, goal: goal)

    described_class.new(payload(initiative)).call

    expect(initiative.reload.goal).to eq(goal)
  end

  it "returns an inline error and makes no changes when the title is blank" do
    initiative = create(:initiative, goal: create(:goal, organization: organization), title: "Untouched")

    result = described_class.new(
      payload(initiative, { "title_block" => { "title" => { "value" => "" } } })
    ).call

    expect(result).to eq(response_action: "errors", errors: { "title_block" => "Please enter a title" })
    expect(initiative.reload.title).to eq("Untouched")
  end

  it "returns an inline error and makes no changes for an unauthorized submitter" do
    initiative = create(:initiative, goal: create(:goal, organization: organization), title: "Untouched")

    result = described_class.new(payload(initiative, user_id: "U_UNRELATED")).call

    expect(result).to eq(response_action: "errors", errors: { "title_block" => "You can't edit this initiative." })
    expect(initiative.reload.title).to eq("Untouched")
  end

  it "allows the initiative's own owner (not just the goal's creator/owners) to edit it" do
    goal = create(:goal, organization: organization)
    initiative_owner = create(:user, organization: organization, provider_uid: "U_INIT_OWNER")
    initiative = create(:initiative, goal: goal, owner: initiative_owner, title: "Untouched")

    result = described_class.new(payload(initiative, user_id: "U_INIT_OWNER")).call

    expect(result).to eq(response_action: "clear")
    expect(initiative.reload.title).to eq("Ship onboarding revamp v2")
  end

  it "resolves the initiative from JSON metadata's initiative_id" do
    initiative = create(:initiative, goal: create(:goal, organization: organization), title: "Untouched")

    result = described_class.new(payload(initiative, metadata: { "initiative_id" => initiative.id })).call

    expect(result).to eq(response_action: "clear")
    expect(initiative.reload.title).to eq("Ship onboarding revamp v2")
  end

  describe "refreshing the initiative's display after a successful update" do
    it "updates the origin card in place when message_ts is present" do
      initiative = create(:initiative, goal: create(:goal, organization: organization), title: "Untouched")

      updater = instance_double(Slack::Request::UpdateMessage)
      allow(Slack::Request::UpdateMessage).to receive(:new).with(workspace).and_return(updater)
      expect(updater).to receive(:update_message) do |channel, ts, message|
        expect(channel).to eq("C_CARD")
        expect(ts).to eq("111.222")
        expect(message[:attachments].first[:blocks].to_s).to include("Ship onboarding revamp v2")
      end
      allow(Slack::Request::SendMessage).to receive(:new)

      described_class.new(
        payload(initiative, metadata: { "initiative_id" => initiative.id, "channel" => "C_CARD", "message_ts" => "111.222" })
      ).call

      expect(Slack::Request::SendMessage).not_to have_received(:new)
    end

    it "posts a fresh InitiativeDisplay in the thread when only channel (+ thread_ts) is present" do
      initiative = create(:initiative, goal: create(:goal, organization: organization), title: "Untouched")

      sender = instance_double(Slack::Request::SendMessage)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_message) do |channel, message|
        expect(channel).to eq("C_THREAD")
        expect(message[:thread_ts]).to eq("9.9")
        expect(message[:attachments].first[:blocks].to_s).to include("Ship onboarding revamp v2")
      end
      allow(Slack::Request::UpdateMessage).to receive(:new)

      described_class.new(
        payload(initiative, metadata: { "initiative_id" => initiative.id, "channel" => "C_THREAD", "thread_ts" => "9.9" })
      ).call

      expect(Slack::Request::UpdateMessage).not_to have_received(:new)
    end

    it "sends no message when neither message_ts nor channel is present" do
      initiative = create(:initiative, goal: create(:goal, organization: organization), title: "Untouched")

      allow(Slack::Request::UpdateMessage).to receive(:new)
      allow(Slack::Request::SendMessage).to receive(:new)

      result = described_class.new(payload(initiative, metadata: { "initiative_id" => initiative.id })).call

      expect(result).to eq(response_action: "clear")
      expect(Slack::Request::UpdateMessage).not_to have_received(:new)
      expect(Slack::Request::SendMessage).not_to have_received(:new)
    end
  end
end
