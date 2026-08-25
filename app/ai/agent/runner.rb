# frozen_string_literal: true

module Ai
  module Agent
    # Runs ONE turn of the agent loop for a conversation, against an already-open
    # AgentRun (status: running). The job (or Ai::Agent::Resume) is responsible
    # for having appended the triggering message — a user message, a system
    # `event`, or a resumed tool result — to the transcript BEFORE calling us; we
    # replay the whole transcript and let RubyLLM's built-in tool loop drive the
    # model, persisting each assistant message + tool result as it happens.
    #
    # Outcomes (all terminal for this turn):
    #   * completed        — model produced a final text reply; rollups written.
    #   * paused_on_tool   — a tool returned Tools::PENDING (a human must act in
    #                        Slack, e.g. submit the goal form). We record the
    #                        pending tool call and stop WITHOUT a tool-result row;
    #                        Ai::Agent::Resume supplies the real result later.
    #   * failed           — the model/provider raised, or the tool-roundtrip
    #                        guard tripped. We record the error and post a short
    #                        apology; we never re-raise (the job must not retry
    #                        into a double-post).
    #
    # Streaming UX: Slack only allows Block Kit blocks in chat.stopStream, never
    # appendStream, so a card can never be inlined mid-message. We therefore
    # stream ONE Slack message PER MODEL COMPLETION rather than one per turn: the
    # caller hands in a `streamer_factory` (a callable returning a fresh
    # Slack::Streamer) instead of a single streamer. One streamer built from the
    # factory (`@decorator`) is reused for the whole turn purely for thread-level
    # decoration (`set_status`/`clear_status`); the "current text segment"
    # (`@segment`) is a separate streamer, lazily opened on the first text chunk
    # of each completion and finalized (`#stop`) right before the next tool call
    # runs, so a tool's card message always lands between two text messages
    # instead of gluing into one. Every decoration call is wrapped so a Slack
    # hiccup can never fail the run.
    class Runner
      PROVIDER = "openrouter"

      # Hard cap on tool <-> model roundtrips within a single turn. A model stuck
      # calling tools in a loop is treated as a failure rather than billed forever.
      MAX_TOOL_ROUNDTRIPS = 8

      # Raised when MAX_TOOL_ROUNDTRIPS is exceeded; caught by our own rescue and
      # turned into a failed run.
      class ToolLoopError < StandardError; end

      # Friendly, present-tense labels for the thread status line shown while a
      # tool call runs (assistant.threads.setStatus). Falls back to a humanized
      # tool name for anything unmapped.
      TASK_LABELS = {
        "list_goals" => "Looking up goals…",
        "get_goal" => "Reading goal details…",
        "save_memory" => "Saving to memory…",
        "forget_memory" => "Updating memory…",
        "show_goal_create_form" => "Preparing a goal form…",
        "edit_goal" => "Updating goal…",
        "pick_goal" => "Finding the right goal…",
        "show_goals" => "Pulling up your goals…",
        "show_goal" => "Pulling up that goal…",
        "record_metric_update" => "Recording metric update…",
        "update_initiative_status" => "Updating initiative…",
        "add_goal_update" => "Logging note…",
        "complete_checkin" => "Wrapping up check-in…"
      }.freeze

      def self.call(...) = new(...).run

      def initialize(agent_run:, streamer_factory:, user: nil)
        @agent_run = agent_run
        @conversation = agent_run.conversation
        @organization = @conversation.organization
        @user = user || infer_turn_author
        @streamer_factory = streamer_factory
        @decorator = streamer_factory.call

        @roundtrips = 0
        @paused = false
        @pending_tool_call = nil
        @current_tool_call = nil
        @segment = nil
        @segment_started_ms = nil
      end

      def run
        @run_started_ms = monotonic_ms
        decorate { @decorator.set_status("is thinking…") }

        chat = build_chat
        @segment_started_ms = monotonic_ms
        response = chat.complete { |chunk| stream_chunk(chunk) }

        @paused ? finish_paused : finish_completed(response)
      rescue StandardError => e
        finish_failed(e)
      end

      private

      attr_reader :agent_run, :conversation, :organization, :user

      # --- Chat construction / transcript replay ------------------------------

      def build_chat
        chat = RubyLLM.chat(
          model: resolved_model,
          provider: PROVIDER.to_sym,
          assume_model_exists: assume_model_exists?,
        )
        chat.with_temperature(0.2)
        chat.with_instructions(SystemPrompt.build(tool_context))
        chat.with_tools(*Ai::Agent::Tools.build_all(tool_context))
        register_callbacks(chat)
        replay_transcript(chat)
        chat
      end

      # Rebuild the RubyLLM message list from our persisted transcript so the
      # model sees the full conversation. Role mapping:
      #   user      -> user
      #   assistant -> assistant (carrying tool_calls when present)
      #   tool      -> tool result (matched by tool_call_id)
      #   event     -> a user-role message wrapped "[event] …" so system-authored
      #                lines (e.g. "user submitted the form; goal X created") read
      #                distinctly from something the human typed.
      def replay_transcript(chat)
        conversation.conversation_messages.each do |message|
          case message.role
          when "user"
            chat.add_message(role: :user, content: message.content.to_s)
          when "assistant"
            chat.add_message(assistant_attributes(message))
          when "tool"
            chat.add_message(role: :tool, content: message.content.to_s, tool_call_id: message.tool_call_id)
          when "event"
            chat.add_message(role: :user, content: "[event] #{message.content}")
          end
        end
      end

      def assistant_attributes(message)
        attrs = { role: :assistant, content: message.content.to_s }
        tool_calls = rebuild_tool_calls(message.tool_calls)
        attrs[:tool_calls] = tool_calls if tool_calls.present?
        attrs
      end

      # Persisted tool_calls jsonb is an array of { id, name, arguments }; RubyLLM
      # expects a Hash keyed by call id of RubyLLM::ToolCall (see the OpenAI
      # provider's format_tool_calls, which iterates `tool_calls.map { |_, tc| }`).
      def rebuild_tool_calls(raw)
        return nil if raw.blank?

        Array(raw).to_h do |tc|
          tc = tc.stringify_keys
          [
            tc["id"],
            RubyLLM::ToolCall.new(
              id: tc["id"],
              name: tc["name"],
              arguments: tc["arguments"] || {},
            )
          ]
        end
      end

      # --- RubyLLM callbacks: persistence, streaming, guardrails --------------

      def register_callbacks(chat)
        chat.after_message { |message| on_message(message) }
        chat.before_tool_call { |tool_call| on_tool_call(tool_call) }
        chat.after_tool_result { |result| on_tool_result(result) }
      end

      # Fires for every message RubyLLM adds — assistant responses AND tool
      # results. We persist + audit assistant messages here; tool results are
      # handled in on_tool_result (which also gets the originating call), so we
      # ignore the tool-role echo to avoid a duplicate row.
      def on_message(message)
        return unless message.role.to_sym == :assistant

        persist_assistant_message(message)
        log_llm_call(message)
      end

      def on_tool_call(tool_call)
        @roundtrips += 1
        if @roundtrips > MAX_TOOL_ROUNDTRIPS
          raise ToolLoopError, "exceeded #{MAX_TOOL_ROUNDTRIPS} tool roundtrips in one turn"
        end

        @current_tool_call = tool_call
        # Finalize the current text segment BEFORE the tool runs, so its Slack
        # message is ordered ahead of the tool's own card message (posted
        # out-of-band via Slack::Request::SendMessage inside #execute).
        finish_segment
        decorate { @decorator.set_status(task_label(tool_call.name)) }
      end

      def on_tool_result(result)
        tool_call = @current_tool_call

        if pending?(result)
          @paused = true
          @pending_tool_call = tool_call
          return
        end

        persist_tool_result(tool_call, result)
        # Next model call's latency is measured from here (after the tool ran).
        @segment_started_ms = monotonic_ms
      end

      def pending?(result)
        result.is_a?(RubyLLM::Tool::Halt) && result.content == Ai::Agent::Tools::PENDING
      end

      # --- Streaming ----------------------------------------------------------

      def stream_chunk(chunk)
        text = chunk.respond_to?(:content) ? chunk.content : nil
        return if text.blank?

        decorate do
          @segment ||= @streamer_factory.call
          @segment.append_text(text)
        end
      end

      # Finalizes (and clears) the current text segment, if one is open. A
      # completion with no text never opens a segment, so this is a no-op for it
      # — no empty Slack message is created.
      def finish_segment
        return unless @segment

        decorate { @segment.stop }
        @segment = nil
      end

      # --- Persistence --------------------------------------------------------

      def persist_assistant_message(message)
        conversation.conversation_messages.create!(
          role: :assistant,
          content: message.content.to_s,
          tool_calls: serialize_tool_calls(message),
        )
      end

      def serialize_tool_calls(message)
        return nil unless message.tool_call?

        message.tool_calls.values.map do |tc|
          { id: tc.id, name: tc.name, arguments: tc.arguments }
        end
      end

      def persist_tool_result(tool_call, result)
        conversation.conversation_messages.create!(
          role: :tool,
          tool_call_id: tool_call&.id,
          content: stringify_result(result),
        )
      end

      def stringify_result(result)
        payload = result.is_a?(RubyLLM::Tool::Halt) ? result.content : result
        payload.is_a?(String) ? payload : payload.to_json
      end

      # --- Audit (one LlmCall per model response) -----------------------------

      def log_llm_call(message)
        latency = @segment_started_ms ? (monotonic_ms - @segment_started_ms) : nil
        # Reset the segment so a follow-up model call in the same turn is timed
        # from now (the tool path resets it again once a tool finishes).
        @segment_started_ms = monotonic_ms

        agent_run.llm_calls.create!(
          organization_id: organization.id,
          user_id: user&.id,
          task: :agent_turn,
          model: message.model_id || resolved_model,
          provider: PROVIDER,
          request_messages: { system: SystemPrompt.build(tool_context) },
          raw_response: raw_body(message),
          parsed_output: { content: message.content.to_s, tool_calls: serialize_tool_calls(message) }.compact,
          prompt_tokens: message.input_tokens,
          completion_tokens: message.output_tokens,
          total_tokens: message.input_tokens.to_i + message.output_tokens.to_i,
          cost: safe_cost(message),
          latency_ms: latency,
          status: :success,
          temperature: 0.2,
        )
      end

      # --- Terminal outcomes --------------------------------------------------

      # The assistant's prose was already streamed delta-by-delta via append_text,
      # so #stop just flushes the buffer and finalizes — no final_markdown needed
      # (passing it would re-send the whole reply). `response` is accepted for
      # symmetry / future use.
      def finish_completed(_response)
        finish_segment
        decorate { @decorator.clear_status }
        agent_run.update!(status: :completed, **rollups)
      end

      def finish_paused
        record_pending_tool_call
        finish_segment
        decorate { @decorator.clear_status }
        agent_run.update!(status: :paused_on_tool, **rollups)
      end

      def finish_failed(error)
        Rails.logger.error("[Ai::Agent::Runner] turn failed: #{error.class}: #{error.message}")
        Bugsnag.notify(error) if defined?(Bugsnag)

        agent_run.update!(status: :failed, error: error_payload(error), **rollups)
        finish_segment
        decorate { @decorator.clear_status }
        post_failure_reply
        nil
      end

      # Merge the call id + name over whatever args the tool already stashed on
      # pending_tool_call (show_goal_create_form writes ["args"]); the sibling
      # id/name bookkeeping is the runner's job (see the tool's #persist_draft).
      def record_pending_tool_call
        tool_call = @pending_tool_call
        pending = (agent_run.pending_tool_call || {}).stringify_keys
        pending["id"] = tool_call&.id
        pending["name"] = tool_call&.name
        agent_run.update!(pending_tool_call: pending)
      end

      def rollups
        calls = agent_run.llm_calls.reload
        {
          input_tokens: calls.sum(:prompt_tokens),
          output_tokens: calls.sum(:completion_tokens),
          cost: calls.sum(:cost),
          duration_ms: @run_started_ms ? (monotonic_ms - @run_started_ms) : nil
        }
      end

      def error_payload(error)
        { class: error.class.name, message: error.message }
      end

      def post_failure_reply
        Slack::Request::SendMessage.new(organization.slack_workspace).send_message(
          conversation.slack_channel_id,
          Slack::Messages::PipelineError.new.to_h.merge(thread_ts: conversation.slack_thread_ts),
        )
      rescue StandardError => e
        Rails.logger.warn("[Ai::Agent::Runner] failed to post failure reply: #{e.class}: #{e.message}")
        Bugsnag.notify(e) if defined?(Bugsnag)
      end

      # --- Helpers ------------------------------------------------------------

      def tool_context
        @tool_context ||= ToolContext.new(
          conversation: conversation,
          organization: organization,
          user: user,
          agent_run: agent_run,
        )
      end

      # When no explicit turn author is given (e.g. a resumed run), fall back to
      # the most recent human-authored message's user.
      def infer_turn_author
        conversation.conversation_messages.where(role: :user).where.not(user_id: nil).order(:created_at).last&.user
      end

      def task_label(tool_name)
        TASK_LABELS.fetch(tool_name.to_s) { tool_name.to_s.humanize }
      end

      # Streamer already degrades internally, but belt-and-braces: a raised Slack
      # error from any decoration must never fail the run.
      def decorate
        yield
      rescue StandardError => e
        Rails.logger.warn("[Ai::Agent::Runner] streamer decoration failed: #{e.class}: #{e.message}")
        Bugsnag.notify(e) if defined?(Bugsnag)
        nil
      end

      def resolved_model
        @resolved_model ||= Rails.application.config.x.ai_models.fetch(:agent)
      end

      def assume_model_exists?
        Rails.application.config.x.ai_assume_model_exists
      end

      def raw_body(message)
        raw = message.respond_to?(:raw) ? message.raw : nil
        return {} if raw.nil?

        body = raw.respond_to?(:body) ? raw.body : raw
        body.is_a?(Hash) || body.is_a?(Array) ? body : { body: body.to_s }
      end

      def safe_cost(message)
        message.cost&.total
      rescue StandardError
        nil
      end

      def monotonic_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      end
    end
  end
end
