require "rails_helper"

# AgentTurnJob resolves org + user, finds-or-creates the thread's Conversation,
# appends the triggering message (applying the resolve-once pause rule), opens an
# AgentRun, and hands off to the runner. The runner is stubbed here; runner
# behavior is covered in spec/ai/agent/runner_spec.rb.
RSpec.describe AgentTurnJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  # Pre-create the user so CreateUserFromSlack finds them without a Slack API call.
  let!(:user) { create(:user, organization: organization, provider_uid: "U_AUTHOR") }

  let(:streamer) { instance_double(Slack::Streamer) }

  before do
    allow(Ai::Agent::Runner).to receive(:call)
    allow(Slack::Streamer).to receive(:new).and_return(streamer)
  end

  def perform(text: nil, event: nil, thread_ts: "1700000000.000100")
    described_class.new.perform(
      slack_team_id: workspace.identifier,
      channel: "C1",
      thread_ts: thread_ts,
      surface: "channel",
      slack_user_id: "U_AUTHOR",
      text: text,
      event: event,
    )
  end

  context "a plain user message" do
    it "creates the conversation, appends the user message, opens a run, and calls the runner" do
      perform(text: "how are my goals doing?")

      conversation = organization.conversations.sole
      expect(conversation.surface).to eq("channel")
      expect(conversation.slack_thread_ts).to eq("1700000000.000100")

      message = conversation.conversation_messages.sole
      expect(message.role).to eq("user")
      expect(message.content).to eq("how are my goals doing?")
      expect(message.user).to eq(user)

      run = conversation.agent_runs.sole
      expect(run).to be_status_running
      expect(Ai::Agent::Runner).to have_received(:call) do |args|
        expect(args[:agent_run]).to eq(run)
        expect(args[:user]).to eq(user)
        # The Runner opens a fresh streamer per model completion, so it's handed
        # a factory (Slack::Streamer.new is stubbed above to always return the
        # same double regardless of call count).
        expect(args[:streamer_factory]).to respond_to(:call)
        expect(args[:streamer_factory].call).to eq(streamer)
      end
    end

    it "reuses an existing conversation for the same thread" do
      existing = create(:conversation, organization: organization, slack_channel_id: "C1",
                                       slack_thread_ts: "1700000000.000100", surface: "channel")

      perform(text: "follow-up")

      expect(organization.conversations.count).to eq(1)
      expect(existing.conversation_messages.reload.map(&:role)).to include("user")
    end
  end

  context "an event message" do
    it "appends an event-role message and proceeds with the turn" do
      perform(event: "user opened the assistant thread")

      conversation = organization.conversations.sole
      message = conversation.conversation_messages.sole
      expect(message.role).to eq("event")
      expect(message.content).to eq("user opened the assistant thread")
      expect(conversation.agent_runs.sole).to be_status_running
      expect(Ai::Agent::Runner).to have_received(:call)
    end
  end

  context "resolve-once: the latest run is still paused on a tool" do
    let!(:conversation) do
      create(:conversation, organization: organization, slack_channel_id: "C1",
                            slack_thread_ts: "1700000000.000100", surface: "channel")
    end
    let!(:paused_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
                         pending_tool_call: { "id" => "call_9", "name" => "show_goal_create_form" })
    end

    it "injects a synthetic tool result, retires the paused run, then runs the new turn" do
      perform(text: "actually, never mind — what's due this quarter?")

      synthetic = conversation.conversation_messages.where(role: "tool").sole
      expect(synthetic.tool_call_id).to eq("call_9")
      expect(synthetic.content).to eq(described_class::SUPERSEDED_PAUSE_RESULT)

      expect(paused_run.reload).to be_status_completed

      new_run = conversation.agent_runs.where(status: "running").sole
      expect(conversation.conversation_messages.where(role: "user").sole.content)
        .to eq("actually, never mind — what's due this quarter?")
      expect(Ai::Agent::Runner).to have_received(:call) do |args|
        expect(args[:agent_run]).to eq(new_run)
        expect(args[:user]).to eq(user)
        expect(args[:streamer_factory].call).to eq(streamer)
      end
    end
  end

  context "when the org can't be resolved" do
    it "no-ops without creating anything" do
      described_class.new.perform(
        slack_team_id: "T_UNKNOWN", channel: "C1", thread_ts: "1.1",
        surface: "channel", slack_user_id: "U_AUTHOR", text: "hi",
      )

      expect(Conversation.count).to eq(0)
      expect(Ai::Agent::Runner).not_to have_received(:call)
    end
  end

  describe "concurrency configuration" do
    it "serializes one perform at a time per thread via a team+channel+thread key" do
      config = described_class.good_job_concurrency_config
      expect(config[:perform_limit]).to eq(1)
      expect(config).not_to have_key(:enqueue_limit)

      job = described_class.new(
        slack_team_id: "T1", channel: "C1", thread_ts: "9.9",
        surface: "channel", slack_user_id: "U1", text: "hi",
      )
      expect(job.good_job_concurrency_key).to eq("agent-turn:T1:C1:9.9")
    end
  end
end
