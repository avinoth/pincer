# frozen_string_literal: true

# A per-message streaming session over Slack's streaming chat API (chat.startStream /
# chat.appendStream / chat.stopStream), used to render an agent's reply token-by-token
# with tool-call ("task") cards.
#
# Construct one per assistant turn with the target `channel:` and `thread_ts:` (streamed
# messages are ALWAYS thread replies). Then:
#
#   streamer = Slack::Streamer.new(workspace, channel: "C1", thread_ts: "111.1")
#   streamer.set_status("is thinking…")
#   streamer.append_text("Here")      # lazily starts the stream, buffers, flushes
#   streamer.append_text(" we go")    # coalesced with the previous append
#   streamer.add_task("Searching goals…")
#   streamer.stop(final_markdown: "Done.")
#
# Reuses Slack::Request::Base for the token'd, auto-refreshing Slack::Web::Client and the
# best-effort SlackInteraction logging via #log_slack_call.
#
# Notes on the slack-ruby-client (3.2.0) wrappers:
# - chat.startStream / chat.appendStream / chat.stopStream ARE wrapped by the gem, but the
#   gem's #chat_appendStream hard-requires `markdown_text`, so task-only appends (which carry
#   only a `chunks` array) go through the raw Slack::Web::Client#post path.
# - The gem does NOT JSON-encode the `chunks` argument (unlike `blocks`), and the Faraday
#   connection is form-encoded, so we JSON-encode `chunks` ourselves — mirroring how the gem
#   handles `blocks`.
class Slack::Streamer < Slack::Request::Base
  # Slack task_display_mode: "dense" collapses consecutive tool calls into one summarized card.
  DEFAULT_TASK_DISPLAY_MODE = "dense"

  # Coalesce buffered token deltas: flush at most this often (seconds). chat.appendStream is
  # rate-limited (~20/min per channel), so we stay well under that.
  FLUSH_INTERVAL = 0.3

  # Per-chunk character cap for task_update / plan_update chunks (Slack limit).
  TASK_MAX_CHARS = 256

  # Slack's hard cap on the `markdown_text` argument. The fallback sends the whole accumulated
  # reply in one chat.postMessage, so we truncate to stay under it (the legacy `text:` field
  # tolerated far more; over-cap markdown_text is rejected outright).
  MARKDOWN_MAX_CHARS = 12_000

  # Monotonic clock; injectable for tests.
  MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(workspace, channel:, thread_ts:, recipient_user_id: nil, recipient_team_id: nil,
                 task_display_mode: DEFAULT_TASK_DISPLAY_MODE, clock: MONOTONIC)
    super(workspace)
    @channel = channel
    @thread_ts = thread_ts
    @recipient_user_id = recipient_user_id
    @recipient_team_id = recipient_team_id
    @task_display_mode = task_display_mode
    @clock = clock

    @buffer = +""
    @full_text = +""
    @last_flush_at = nil
    @stream_ts = nil
    @started = false
    @degraded = false
    @stopped = false
  end

  attr_reader :stream_ts

  # Opens the streaming message. Safe to call directly, but callers can also just append —
  # the first #append_text / #add_task lazily starts the stream. Returns the stream ts (or
  # nil if start failed and we've fallen back to a plain postMessage at #stop).
  def start
    return @stream_ts if @started || @degraded

    payload = start_payload
    response = log_slack_call("chat.startStream", payload) { client.chat_startStream(**payload) }
    @stream_ts = response&.[]("ts")
    @started = true
    @stream_ts
  rescue => e
    # Streaming may be unavailable (feature flag, scope, older workspace). Degrade to a single
    # plain chat.postMessage carrying the accumulated text at #stop time — the agent still replies.
    @degraded = true
    Rails.logger.warn("[Slack::Streamer] startStream failed, degrading to postMessage: #{e.class}: #{e.message}")
    Bugsnag.notify(e)
    nil
  end

  # Append a markdown delta. Buffered and flushed at most every FLUSH_INTERVAL so LLM token
  # deltas don't spam the API.
  def append_text(markdown)
    return self if markdown.blank?

    ensure_started
    @full_text << markdown
    @buffer << markdown
    flush if flush_due?
    self
  end

  # Emit a tool-call card. Truncated to TASK_MAX_CHARS and sent as a `task_update` chunk.
  def add_task(text, status: "in_progress")
    return self if text.blank?

    ensure_started
    title = text.to_s[0, TASK_MAX_CHARS]

    # Streaming unavailable: task labels are ephemeral progress, not reply content.
    # Drop them so they never post as trailing chat text after out-of-band tool
    # messages (e.g. a tool's own chat.postMessage). The run-level
    # set_status("is thinking…") still signals progress.
    return self if @degraded

    flush # keep ordering: any pending text lands before the task card
    chunk = { type: "task_update", id: SecureRandom.hex(8), title: title, status: status }
    payload = { channel: @channel, ts: @stream_ts, chunks: [ chunk ].to_json }
    # Raw post: the gem's #chat_appendStream requires markdown_text, which task-only appends lack.
    log_slack_call("chat.appendStream", payload) { client.post("chat.appendStream", payload) }
    self
  end

  # Flush the remainder and finalize the stream. Idempotent. Falls back to chat.postMessage if
  # the stream never started (degraded) or if stopStream itself fails.
  def stop(final_markdown: nil)
    return self if @stopped

    @stopped = true
    return fallback_post(final_markdown) if @degraded || @stream_ts.nil?

    flush
    payload = { channel: @channel, ts: @stream_ts, markdown_text: final_markdown }.compact
    log_slack_call("chat.stopStream", payload) { client.chat_stopStream(**payload) }
    self
  rescue => e
    Rails.logger.warn("[Slack::Streamer] stopStream failed, falling back to postMessage: #{e.class}: #{e.message}")
    Bugsnag.notify(e)
    fallback_post(final_markdown)
  end

  # --- Assistant-thread decoration (best-effort; never fatal) ---

  # assistant.threads.setStatus — works in regular channel threads with chat:write. An empty
  # string clears the status.
  def set_status(text)
    best_effort do
      client.assistant_threads_setStatus(channel_id: @channel, thread_ts: @thread_ts, status: text.to_s)
    end
  end

  def clear_status
    set_status("")
  end

  # assistant.threads.setTitle — assistant (DM split-view) threads only; needs assistant:write.
  def set_title(title)
    best_effort do
      client.assistant_threads_setTitle(channel_id: @channel, thread_ts: @thread_ts, title: title.to_s)
    end
  end

  # assistant.threads.setSuggestedPrompts — assistant threads only. `prompts` is an array of
  # { title:, message: } hashes.
  def set_suggested_prompts(prompts, title: nil)
    payload = { channel_id: @channel, thread_ts: @thread_ts, prompts: prompts, title: title }.compact
    best_effort { client.assistant_threads_setSuggestedPrompts(**payload) }
  end

  private

  def ensure_started
    start unless @started || @degraded
  end

  def flush_due?
    now = @clock.call
    @last_flush_at.nil? || (now - @last_flush_at) >= FLUSH_INTERVAL
  end

  def flush
    return if @degraded || @buffer.empty? || @stream_ts.nil?

    text = @buffer
    @buffer = +""
    @last_flush_at = @clock.call
    payload = { channel: @channel, ts: @stream_ts, markdown_text: text }
    log_slack_call("chat.appendStream", payload) { client.chat_appendStream(**payload) }
  end

  def fallback_post(final_markdown)
    text = [ @full_text, final_markdown ].compact.join.strip
    return self if text.blank?

    # Use markdown_text (not the legacy `text:` mrkdwn field) so the agent's GitHub-flavored
    # markdown — bold, headings, and tables — renders instead of showing up verbatim. The two
    # fields are mutually exclusive, so we send markdown_text alone.
    payload = { channel: @channel, thread_ts: @thread_ts, markdown_text: markdown_cap(text) }
    log_slack_call("chat.postMessage", payload) { client.chat_postMessage(**payload) }
    self
  end

  # Truncate to Slack's markdown_text limit, appending an ellipsis when we cut.
  def markdown_cap(text)
    return text if text.length <= MARKDOWN_MAX_CHARS

    "#{text[0, MARKDOWN_MAX_CHARS - 1]}…"
  end

  def start_payload
    {
      channel: @channel,
      thread_ts: @thread_ts,
      task_display_mode: @task_display_mode,
      recipient_user_id: @recipient_user_id,
      recipient_team_id: @recipient_team_id
    }.compact
  end

  def best_effort
    yield
  rescue => e
    Rails.logger.warn("[Slack::Streamer] non-fatal: #{e.class}: #{e.message}")
    Bugsnag.notify(e)
    nil
  end
end
