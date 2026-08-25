require "rails_helper"

# Exercises Ai::Agent::Runner with the LLM stubbed at the RubyLLM boundary. A
# FakeChat stands in for RubyLLM.chat and drives the same callback sequence the
# real gem's tool loop does (after_message per model response, before_tool_call /
# after_tool_result per tool, a Tool::Halt to signal PENDING), so we assert the
# runner's persistence, streaming, audit, pause and failure behavior end-to-end.
RSpec.describe Ai::Agent::Runner do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1", surface: "channel") }
  let(:user) { create(:user, organization: organization) }
  let(:agent_run) { create(:agent_run, conversation: conversation, status: "running") }

  # A single streamer double shared by the decorator and every text segment —
  # sufficient for specs that only assert aggregate append_text/stop/set_status
  # calls. Specs that need to assert PER-SEGMENT ordering build their own
  # multi-double factory instead (see "segmented streaming" below).
  let(:streamer) do
    instance_double(
      Slack::Streamer,
      set_status: nil, clear_status: nil, append_text: nil, add_task: nil, stop: nil,
    )
  end
  let(:streamer_factory) { -> { streamer } }

  before do
    # The turn's triggering user message is appended by the job before the runner
    # runs; seed it here so the transcript replays a real turn.
    create(:conversation_message, conversation: conversation, role: "user", user: user,
                                  content: "how are my goals doing?")
    allow(RubyLLM).to receive(:chat).and_return(fake_chat)
  end

  # --- Fake RubyLLM chat ---------------------------------------------------

  # Build a real RubyLLM::Message so cost/token/tool_call accessors behave.
  def assistant_message(content: "", tool_calls: nil, input: 10, output: 5, model: "anthropic/claude-sonnet-4.5")
    RubyLLM::Message.new(
      role: :assistant, content: content, tool_calls: tool_calls,
      input_tokens: input, output_tokens: output, model_id: model,
      raw: instance_double(Faraday::Response, body: { "ok" => true }),
    )
  end

  def tool_call(id:, name:, arguments: {})
    RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments)
  end

  # A minimal, faithful stand-in for RubyLLM::Chat. `script` is an ordered list of
  # model responses; each is one of:
  #   { type: :text, message: }                        final assistant reply
  #   { type: :tool, message:, tool_call:, result:,
  #     on_tool_execute: }                              assistant asks for a tool;
  #                                                      on_tool_execute (optional)
  #                                                      simulates a card-posting
  #                                                      tool's side effect, fired
  #                                                      between before_tool_call
  #                                                      and after_tool_result —
  #                                                      exactly where the real
  #                                                      Tool#execute runs.
  #   { type: :pending, message:, tool_call: }          tool returns PENDING (Halt)
  # Any step's message.content, if present, streams as a chunk before its
  # callbacks fire — mirroring RubyLLM streaming narration ahead of a tool call.
  class FakeChat
    def initialize(script)
      @script = script
      @cb = {}
    end

    def with_temperature(*) = self
    def with_instructions(*) = self
    def with_tools(*) = self
    def add_message(*) = self
    def after_message(&b) = tap { @cb[:after_message] = b }
    def before_tool_call(&b) = tap { @cb[:before_tool_call] = b }
    def after_tool_result(&b) = tap { @cb[:after_tool_result] = b }

    def complete(&stream)
      @script.each do |step|
        message = step[:message]
        stream&.call(RubyLLM::Chunk.new(role: :assistant, content: message.content)) if message.content.present?
        fire(:after_message, message)

        case step[:type]
        when :text
          return message
        when :tool
          fire(:before_tool_call, step[:tool_call])
          step[:on_tool_execute]&.call
          fire(:after_tool_result, step[:result])
          fire(:after_message, RubyLLM::Message.new(role: :tool, content: step[:result].to_json,
                                                    tool_call_id: step[:tool_call].id))
        when :pending
          fire(:before_tool_call, step[:tool_call])
          step[:on_tool_execute]&.call
          halt = RubyLLM::Tool::Halt.new(Ai::Agent::Tools::PENDING)
          fire(:after_tool_result, halt)
          return halt
        end
      end
    end

    private

    def fire(name, *args) = @cb[name]&.call(*args)
  end

  let(:script) { [ { type: :text, message: assistant_message(content: "Your goals look healthy.") } ] }
  let(:fake_chat) { FakeChat.new(script) }

  def messages_by_id
    conversation.conversation_messages.reorder(:id).to_a
  end

  # --- Text-only turn ------------------------------------------------------

  context "a text-only turn" do
    it "persists the assistant reply, completes the run with rollups, and streams" do
      described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

      roles = messages_by_id.map(&:role)
      expect(roles).to eq(%w[user assistant])
      expect(messages_by_id.last.content).to eq("Your goals look healthy.")

      agent_run.reload
      expect(agent_run).to be_status_completed
      expect(agent_run.input_tokens).to eq(10)
      expect(agent_run.output_tokens).to eq(5)
      expect(agent_run.duration_ms).to be_a(Integer)

      expect(agent_run.llm_calls.count).to eq(1)
      call = agent_run.llm_calls.sole
      expect(call.task).to eq("agent_turn")
      expect(call).to be_status_success
      expect(call.prompt_tokens).to eq(10)
      expect(call.organization_id).to eq(organization.id)

      expect(streamer).to have_received(:set_status).with("is thinking…")
      expect(streamer).to have_received(:append_text).with("Your goals look healthy.")
      expect(streamer).to have_received(:stop).once
      expect(streamer).to have_received(:clear_status)
      expect(streamer).not_to have_received(:add_task)
    end
  end

  # --- One read-tool roundtrip --------------------------------------------

  context "a turn with one read-tool roundtrip" do
    let(:script) do
      [
        {
          type: :tool,
          message: assistant_message(content: "", tool_calls: { "call_1" => tool_call(id: "call_1", name: "list_goals") }),
          tool_call: tool_call(id: "call_1", name: "list_goals"),
          result: [ { "id" => 1, "title" => "Grow activation" } ]
        },
        { type: :text, message: assistant_message(content: "You have 1 goal.", input: 20, output: 8) }
      ]
    end

    it "persists the tool-call + tool-result rows in order and logs a call per model response" do
      described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

      rows = messages_by_id
      expect(rows.map(&:role)).to eq(%w[user assistant tool assistant])

      tool_call_row = rows[1]
      expect(tool_call_row.tool_calls.first["name"]).to eq("list_goals")
      expect(tool_call_row.tool_calls.first["id"]).to eq("call_1")

      tool_result_row = rows[2]
      expect(tool_result_row.tool_call_id).to eq("call_1")
      expect(tool_result_row.content).to include("Grow activation")

      expect(streamer).to have_received(:set_status).with("Looking up goals…")
      expect(streamer).not_to have_received(:add_task)
      expect(agent_run.llm_calls.count).to eq(2)
      expect(agent_run.reload).to be_status_completed
    end
  end

  # --- Pause on show_goal_create_form -------------------------------------

  context "a turn that pauses on show_goal_create_form" do
    let(:script) do
      calls = { "call_9" => tool_call(id: "call_9", name: "show_goal_create_form") }
      [
        {
          type: :pending,
          message: assistant_message(content: "Here's a draft.", tool_calls: calls),
          tool_call: tool_call(id: "call_9", name: "show_goal_create_form")
        }
      ]
    end

    before do
      # The real tool stashes its draft args before returning PENDING; simulate
      # that so we can assert the runner merges id/name WITHOUT clobbering args.
      agent_run.update!(pending_tool_call: { "args" => { "title" => "Grow activation" } })
    end

    it "records the pending tool call, pauses, and writes no tool-result row" do
      described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

      agent_run.reload
      expect(agent_run).to be_status_paused_on_tool

      pending = agent_run.pending_tool_call
      expect(pending["id"]).to eq("call_9")
      expect(pending["name"]).to eq("show_goal_create_form")
      expect(pending["args"]).to eq("title" => "Grow activation")

      expect(messages_by_id.map(&:role)).to eq(%w[user assistant])
      expect(conversation.conversation_messages.where(role: "tool")).to be_empty

      expect(streamer).to have_received(:stop)
      expect(streamer).to have_received(:clear_status)
    end
  end

  # --- Segmented streaming (one Slack message per model completion) --------
  #
  # These specs use a factory that hands out DISTINCT doubles per call — the
  # first for @decorator (thread-level set_status/clear_status), the rest, in
  # order, for each text segment — so we can assert per-message content and
  # ordering instead of one glued append_text stream.

  context "segmented streaming" do
    let(:decorator) { instance_double(Slack::Streamer, set_status: nil, clear_status: nil) }
    let(:segment_1) { instance_double(Slack::Streamer, append_text: nil, stop: nil) }
    let(:segment_2) { instance_double(Slack::Streamer, append_text: nil, stop: nil) }
    let(:streamer_queue) { [ decorator, segment_1, segment_2 ] }
    let(:streamer_factory) { -> { streamer_queue.shift } }

    context "two text completions around a no-card tool (list_goals)" do
      let(:script) do
        [
          {
            type: :tool,
            message: assistant_message(content: "Let me check your goals…",
                                       tool_calls: { "call_1" => tool_call(id: "call_1", name: "list_goals") }),
            tool_call: tool_call(id: "call_1", name: "list_goals"),
            result: [ { "id" => 1, "title" => "Grow activation" } ]
          },
          { type: :text, message: assistant_message(content: "You have 1 goal.", input: 20, output: 8) }
        ]
      end

      it "streams each completion into its own segment instead of one glued string" do
        described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

        expect(segment_1).to have_received(:append_text).with("Let me check your goals…")
        expect(segment_1).to have_received(:stop)
        expect(segment_1).not_to have_received(:append_text).with("You have 1 goal.")
        expect(segment_2).to have_received(:append_text).with("You have 1 goal.")
        expect(segment_2).to have_received(:stop)
        expect(decorator).to have_received(:set_status).with("Looking up goals…")
      end
    end

    context "narration before a card-posting tool, then a follow-up completion" do
      let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }
      let(:call_log) { [] }

      let(:script) do
        [
          {
            type: :tool,
            message: assistant_message(content: "I can update that for you:",
                                       tool_calls: { "call_1" => tool_call(id: "call_1", name: "edit_goal") }),
            tool_call: tool_call(id: "call_1", name: "edit_goal"),
            result: { "id" => 1, "title" => "Grow activation" },
            on_tool_execute: -> {
              call_log << :card_posted
              Slack::Request::SendMessage.new(organization.slack_workspace).send_message("C1", {})
            }
          },
          { type: :text, message: assistant_message(content: "Done! Renamed it.", input: 20, output: 8) }
        ]
      end

      before do
        allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
        allow(segment_1).to receive(:stop) { call_log << :segment_1_stopped }
        allow(segment_2).to receive(:append_text) { call_log << :segment_2_text }
      end

      it "finalizes the narration segment before the tool's card, then opens a new segment for the reply" do
        described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

        expect(segment_1).to have_received(:append_text).with("I can update that for you:")
        expect(decorator).to have_received(:set_status).with("Updating goal…")
        expect(segment_2).to have_received(:append_text).with("Done! Renamed it.")
        expect(call_log).to eq(%i[segment_1_stopped card_posted segment_2_text])
      end
    end

    context "pause/resume still finalizes the open segment and clears status" do
      let(:script) do
        calls = { "call_9" => tool_call(id: "call_9", name: "show_goal_create_form") }
        [
          {
            type: :pending,
            message: assistant_message(content: "Here's a draft.", tool_calls: calls),
            tool_call: tool_call(id: "call_9", name: "show_goal_create_form")
          }
        ]
      end

      it "stops the segment opened by the pre-pause narration and clears the decorator status" do
        described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

        expect(agent_run.reload).to be_status_paused_on_tool
        expect(segment_1).to have_received(:append_text).with("Here's a draft.")
        expect(segment_1).to have_received(:stop)
        expect(decorator).to have_received(:set_status).with("Preparing a goal form…")
        expect(decorator).to have_received(:clear_status)
      end
    end

    context "failure after some narration was already streamed" do
      let(:raising_chat) do
        Class.new do
          def with_temperature(*) = self
          def with_instructions(*) = self
          def with_tools(*) = self
          def add_message(*) = self
          def after_message(&b) = self
          def before_tool_call(&b) = self
          def after_tool_result(&b) = self

          def complete(&stream)
            stream&.call(RubyLLM::Chunk.new(role: :assistant, content: "Working on it…"))
            raise RubyLLM::Error.new(nil, "boom")
          end
        end.new
      end

      before do
        allow(RubyLLM).to receive(:chat).and_return(raising_chat)
        allow(Slack::Request::SendMessage).to receive(:new)
          .and_return(instance_double(Slack::Request::SendMessage, send_message: nil))
      end

      it "stops the open segment and clears status even though the model raised mid-stream" do
        described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

        expect(agent_run.reload).to be_status_failed
        expect(segment_1).to have_received(:append_text).with("Working on it…")
        expect(segment_1).to have_received(:stop)
        expect(decorator).to have_received(:clear_status)
      end
    end
  end

  # --- Failure path --------------------------------------------------------

  context "when the model raises" do
    let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

    before do
      allow(fake_chat).to receive(:complete).and_raise(RubyLLM::Error.new(nil, "boom"))
      allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
    end

    it "fails the run, records the error, posts an apology, and does not re-raise" do
      expect { described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user) }.not_to raise_error

      agent_run.reload
      expect(agent_run).to be_status_failed
      expect(agent_run.error["message"]).to include("boom")

      expect(send_message).to have_received(:send_message) do |channel, payload|
        expect(channel).to eq("C1")
        expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      end
      expect(streamer).to have_received(:clear_status)
    end
  end

  # --- Tool-roundtrip guardrail -------------------------------------------

  context "when the tool loop exceeds the roundtrip cap" do
    let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

    let(:script) do
      (1..(described_class::MAX_TOOL_ROUNDTRIPS + 1)).map do |n|
        calls = { "c#{n}" => tool_call(id: "c#{n}", name: "list_goals") }
        {
          type: :tool,
          message: assistant_message(content: "", tool_calls: calls),
          tool_call: tool_call(id: "c#{n}", name: "list_goals"),
          result: [ { "id" => n } ]
        }
      end
    end

    before { allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message) }

    it "fails the run with a roundtrip error" do
      described_class.call(agent_run: agent_run, streamer_factory: streamer_factory, user: user)

      agent_run.reload
      expect(agent_run).to be_status_failed
      expect(agent_run.error["class"]).to eq("Ai::Agent::Runner::ToolLoopError")
      expect(send_message).to have_received(:send_message)
    end
  end
end
