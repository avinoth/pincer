require "rails_helper"

RSpec.describe AssistantThreadStartedJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let!(:user) { create(:user, organization: organization, provider_uid: "U1", full_name: "Ada Lovelace") }

  let(:sender) { instance_double(Slack::Request::SendMessage) }
  let(:streamer) { instance_double(Slack::Streamer, set_suggested_prompts: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    allow(sender).to receive(:send_message)
    allow(Slack::Streamer).to receive(:new).and_return(streamer)
  end

  def perform(context: {})
    described_class.new.perform(
      slack_team_id: workspace.identifier,
      channel: "D1",
      thread_ts: "1700000000.000100",
      slack_user_id: "U1",
      context: context,
    )
  end

  it "creates an assistant-surface Conversation for the thread" do
    perform

    conversation = organization.conversations.sole
    expect(conversation).to be_surface_assistant
    expect(conversation.slack_channel_id).to eq("D1")
    expect(conversation.slack_thread_ts).to eq("1700000000.000100")
  end

  it "seeds context_hint from the started event's context channel, if present" do
    perform(context: { "channel_id" => "C9" })

    expect(organization.conversations.sole.context_hint).to eq("user is viewing #C9")
  end

  it "posts the rich welcome to a first-time user (greeted_at nil) and stamps greeted_at" do
    expect(user.greeted_at).to be_nil

    perform

    expect(sender).to have_received(:send_message) do |channel, message|
      expect(channel).to eq("D1")
      expect(message[:thread_ts]).to eq("1700000000.000100")
      expect(message[:text]).to eq("Hi Ada! I'm Pincer — here's what I can help you with.")
    end
    expect(user.reload.greeted_at).to be_present
  end

  it "posts the plain greeting to a returning user (greeted_at set) without re-stamping" do
    original_time = 1.day.ago
    user.update!(greeted_at: original_time)

    perform

    expect(sender).to have_received(:send_message) do |channel, message|
      expect(channel).to eq("D1")
      expect(message[:thread_ts]).to eq("1700000000.000100")
      expect(message[:text]).to eq("Hello Ada! I'm Pincer — what can I do for you today?")
    end
    expect(user.reload.greeted_at).to be_within(1.second).of(original_time)
  end

  it "sets the thread's suggested prompts" do
    perform

    expect(streamer).to have_received(:set_suggested_prompts).with(
      [
        { title: "Create a goal for this quarter", message: "Create a goal for this quarter" },
        { title: "How are my goals doing?", message: "How are my goals doing?" }
      ]
    )
  end

  it "reuses an existing conversation for the same thread" do
    create(:conversation, organization: organization, slack_channel_id: "D1",
                          slack_thread_ts: "1700000000.000100", surface: "assistant")

    perform

    expect(organization.conversations.count).to eq(1)
  end

  it "does nothing when the workspace can't be resolved" do
    described_class.new.perform(
      slack_team_id: "unknown", channel: "D1", thread_ts: "1.2", slack_user_id: "U1", context: {},
    )

    expect(sender).not_to have_received(:send_message)
  end
end
