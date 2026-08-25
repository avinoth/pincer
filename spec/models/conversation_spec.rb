require "rails_helper"

RSpec.describe Conversation do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:conversation_messages).dependent(:destroy) }
  it { is_expected.to have_many(:agent_runs).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:slack_channel_id) }
  it { is_expected.to validate_presence_of(:slack_thread_ts) }

  it do
    is_expected.to define_enum_for(:surface)
      .with_values(assistant: "assistant", channel: "channel", dm: "dm")
      .backed_by_column_of_type(:string)
      .with_prefix
  end

  it "requires a unique thread per organization/channel" do
    conversation = create(:conversation)

    duplicate = build(:conversation,
      organization: conversation.organization,
      slack_channel_id: conversation.slack_channel_id,
      slack_thread_ts: conversation.slack_thread_ts)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows the same thread ts in a different channel" do
    conversation = create(:conversation)

    other = build(:conversation,
      organization: conversation.organization,
      slack_channel_id: "C_OTHER",
      slack_thread_ts: conversation.slack_thread_ts)

    expect { other.save!(validate: false) }.not_to raise_error
  end

  describe "#conversation_messages" do
    it "returns messages ordered oldest first" do
      conversation = create(:conversation)
      second = create(:conversation_message, conversation: conversation, created_at: 1.minute.ago)
      first = create(:conversation_message, conversation: conversation, created_at: 2.minutes.ago)

      expect(conversation.conversation_messages).to eq([ first, second ])
    end
  end

  describe "#latest_run" do
    it "returns the most recently created agent run" do
      conversation = create(:conversation)
      older = create(:agent_run, conversation: conversation, created_at: 2.minutes.ago)
      newer = create(:agent_run, conversation: conversation, created_at: 1.minute.ago)

      expect(conversation.latest_run).to eq(newer)
      expect(conversation.latest_run).not_to eq(older)
    end

    it "returns nil when there are no runs" do
      conversation = create(:conversation)
      expect(conversation.latest_run).to be_nil
    end
  end
end
