# frozen_string_literal: true

module Ai
  module Agent
    # Resolves a paused agent run. When a run pauses on a human-in-the-loop tool
    # (show_goal_create_form), it persists AgentRun#pending_tool_call and exits;
    # the real tool result only exists once the human acts in Slack (submits the
    # goal-creation modal). Checkpoint 5's modal-submission handler calls us with
    # that result:
    #
    #   Ai::Agent::Resume.call(
    #     agent_run:  run,
    #     tool_result: { goal_id: 42, title: "Grow activation", ... },
    #   )
    #
    # We append the tool-result message (matched to the pending call id), flip the
    # run back to running, and re-enter the Runner so the model reacts to the
    # result — narrating the outcome, and possibly calling more tools before the
    # normal completion rules apply.
    #
    # `tool_result` may be any JSON-able value (Hash / Array / String); it is
    # stored as the tool message's content the same way the runner stores a live
    # tool result, so the model sees it identically.
    class Resume
      class NotPausedError < StandardError; end

      def self.call(...) = new(...).call

      def initialize(agent_run:, tool_result:, recipient_user_id: nil, streamer_factory: nil)
        @agent_run = agent_run
        @tool_result = tool_result
        @recipient_user_id = recipient_user_id
        @streamer_factory = streamer_factory
      end

      def call
        unless agent_run.status_paused_on_tool?
          raise NotPausedError, "AgentRun ##{agent_run.id} is #{agent_run.status}, not paused_on_tool"
        end

        append_tool_result
        agent_run.update!(status: :running)

        Runner.call(agent_run: agent_run, streamer_factory: streamer_factory || build_streamer_factory)
      end

      private

      attr_reader :agent_run, :tool_result, :recipient_user_id, :streamer_factory

      def append_tool_result
        conversation.conversation_messages.create!(
          role: :tool,
          tool_call_id: pending_tool_call_id,
          content: stringify(tool_result),
        )
      end

      def pending_tool_call_id
        (agent_run.pending_tool_call || {}).stringify_keys["id"]
      end

      def stringify(result)
        result.is_a?(String) ? result : result.to_json
      end

      def conversation
        @conversation ||= agent_run.conversation
      end

      # Returns a callable that mints a fresh Slack::Streamer per call — the
      # Runner opens one per model completion (plus one for thread-level
      # decoration), not one per turn (see Runner's streaming UX note).
      def build_streamer_factory
        -> {
          Slack::Streamer.new(
            conversation.organization.slack_workspace,
            channel: conversation.slack_channel_id,
            thread_ts: conversation.slack_thread_ts,
            recipient_user_id: recipient_user_id,
          )
        }
      end
    end
  end
end
