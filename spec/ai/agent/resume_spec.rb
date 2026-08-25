require "rails_helper"

# Ai::Agent::Resume resolves a paused run: it appends the real tool result (from
# a later Slack interaction) and re-enters the runner. The runner itself is
# stubbed here except in the "continues the loop" case, which drives it through a
# FakeChat to prove the run reaches completion.
RSpec.describe Ai::Agent::Resume do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:user) { create(:user, organization: organization) }

  let(:streamer) do
    instance_double(Slack::Streamer, set_status: nil, clear_status: nil, append_text: nil, add_task: nil, stop: nil)
  end
  let(:streamer_factory) { -> { streamer } }

  let(:agent_run) do
    create(:agent_run, conversation: conversation, status: "paused_on_tool",
                       pending_tool_call: { "id" => "call_9", "name" => "show_goal_create_form",
                                            "args" => { "title" => "Grow activation" } })
  end

  before do
    # A balanced transcript up to the pause: the user's turn + the assistant
    # tool-call message that triggered the form.
    create(:conversation_message, conversation: conversation, role: "user", user: user, content: "new goal")
    create(:conversation_message, conversation: conversation, role: "assistant", content: "Here's a draft.",
                                  tool_calls: [ { "id" => "call_9", "name" => "show_goal_create_form", "arguments" => {} } ])
  end

  context "when the run is paused" do
    it "appends the tool result with the pending call id, flips to running, and re-enters the runner" do
      allow(Ai::Agent::Runner).to receive(:call)

      described_class.call(
        agent_run: agent_run,
        tool_result: { goal_id: 42, title: "Grow activation" },
        streamer_factory: streamer_factory,
      )

      tool_row = conversation.conversation_messages.where(role: "tool").sole
      expect(tool_row.tool_call_id).to eq("call_9")
      expect(tool_row.content).to include("42")

      expect(Ai::Agent::Runner).to have_received(:call).with(agent_run: agent_run, streamer_factory: streamer_factory)
    end

    it "drives the runner through to completion" do
      final = RubyLLM::Message.new(role: :assistant, content: "Created 'Grow activation'. Nice.",
                                   input_tokens: 5, output_tokens: 3, model_id: "anthropic/claude-sonnet-4.5",
                                   raw: instance_double(Faraday::Response, body: {}))
      # Minimal chat stand-in: on #complete, fire the runner's after_message
      # callback with a final text reply, exactly as the gem's loop would.
      captured = nil
      fake_chat = instance_double(
        RubyLLM::Chat, with_temperature: nil, with_instructions: nil, with_tools: nil,
        add_message: nil, before_tool_call: nil, after_tool_result: nil,
      )
      allow(fake_chat).to receive(:after_message) { |&b| captured = b; fake_chat }
      allow(fake_chat).to receive(:complete) do |&_stream|
        captured&.call(final)
        final
      end
      allow(RubyLLM).to receive(:chat).and_return(fake_chat)

      described_class.call(agent_run: agent_run, tool_result: { goal_id: 42 }, streamer_factory: streamer_factory)

      expect(agent_run.reload).to be_status_completed
      expect(conversation.conversation_messages.where(role: "assistant").last.content).to include("Created")
    end
  end

  context "when the run is not paused" do
    it "raises rather than resuming" do
      agent_run.update!(status: "running")

      expect do
        described_class.call(agent_run: agent_run, tool_result: {}, streamer_factory: streamer_factory)
      end.to raise_error(Ai::Agent::Resume::NotPausedError)
    end
  end
end
