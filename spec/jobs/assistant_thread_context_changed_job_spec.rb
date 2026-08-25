require "rails_helper"

RSpec.describe AssistantThreadContextChangedJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let!(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "D1",
                          slack_thread_ts: "1700000000.000100", surface: "assistant")
  end

  def perform(context: { "channel_id" => "C9" })
    described_class.new.perform(
      slack_team_id: workspace.identifier,
      channel: "D1",
      thread_ts: "1700000000.000100",
      context: context,
    )
  end

  it "updates the conversation's context_hint from the new context channel" do
    perform

    expect(conversation.reload.context_hint).to eq("user is viewing #C9")
  end

  it "does not enqueue or run any agent turn" do
    expect { perform }.not_to have_enqueued_job(AgentTurnJob)
  end

  it "does nothing when there is no conversation for the thread yet" do
    other = create(:conversation, organization: organization, slack_channel_id: "D2",
                                  slack_thread_ts: "9.9", surface: "assistant")

    described_class.new.perform(
      slack_team_id: workspace.identifier, channel: "D_UNKNOWN", thread_ts: "0.0", context: { "channel_id" => "C9" },
    )

    expect(other.reload.context_hint).to be_nil
  end

  it "does nothing when the context has no channel_id" do
    perform(context: {})

    expect(conversation.reload.context_hint).to be_nil
  end
end
