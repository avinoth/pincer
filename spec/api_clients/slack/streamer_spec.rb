require "rails_helper"

RSpec.describe Slack::Streamer do
  let(:organization) { create(:organization) }
  let(:workspace) { create(:slack_workspace, organization: organization) }
  let(:client) { instance_double(Slack::Web::Client) }

  # Controllable monotonic clock: `now[0]` is the current reading; tests advance it.
  let(:now) { [ 1000.0 ] }
  let(:clock) { -> { now[0] } }

  let(:streamer) do
    described_class.new(workspace, channel: "C1", thread_ts: "111.1", clock: clock)
  end

  before do
    allow(streamer).to receive(:client).and_return(client)
    # Silence best-effort logging noise / avoid enqueuing real jobs.
    allow(LogSlackInteractionJob).to receive(:perform_later)
    allow(client).to receive(:chat_startStream)
      .and_return(Slack::Messages::Message.new("ok" => true, "ts" => "999.1"))
    allow(client).to receive(:chat_appendStream)
    allow(client).to receive(:chat_stopStream)
    allow(client).to receive(:chat_postMessage)
    allow(client).to receive(:post)
    allow(client).to receive(:assistant_threads_setStatus)
  end

  describe "lazy start" do
    it "opens the stream in dense mode on the first append and records the ts" do
      streamer.append_text("hello")

      expect(client).to have_received(:chat_startStream).with(
        hash_including(channel: "C1", thread_ts: "111.1", task_display_mode: "dense"),
      )
      expect(streamer.stream_ts).to eq("999.1")
    end

    it "does not start twice across multiple appends" do
      streamer.append_text("a")
      now[0] += 1.0
      streamer.append_text("b")

      expect(client).to have_received(:chat_startStream).once
    end
  end

  describe "buffering" do
    it "coalesces two rapid appends into a single appendStream call" do
      streamer.append_text("foo") # flushes immediately (first flush)
      streamer.append_text("bar") # within FLUSH_INTERVAL -> buffered, no call

      expect(client).to have_received(:chat_appendStream).once
      expect(client).to have_received(:chat_appendStream).with(
        hash_including(channel: "C1", ts: "999.1", markdown_text: "foo"),
      )
    end

    it "flushes again once the flush interval has elapsed" do
      streamer.append_text("foo")
      now[0] += described_class::FLUSH_INTERVAL + 0.01
      streamer.append_text("bar")

      expect(client).to have_received(:chat_appendStream).twice
      expect(client).to have_received(:chat_appendStream).with(
        hash_including(markdown_text: "bar"),
      )
    end
  end

  describe "#add_task" do
    it "truncates the task title to 256 chars and sends a task_update chunk" do
      streamer.add_task("x" * 400)

      expect(client).to have_received(:post) do |method, payload|
        expect(method).to eq("chat.appendStream")
        chunks = JSON.parse(payload[:chunks])
        expect(chunks.size).to eq(1)
        expect(chunks.first["type"]).to eq("task_update")
        expect(chunks.first["title"].length).to eq(256)
      end
    end
  end

  describe "#stop" do
    it "flushes the remainder and finalizes with stopStream" do
      streamer.append_text("foo")            # flushes "foo"
      streamer.append_text("bar")            # buffered
      streamer.stop(final_markdown: "done")  # flushes "bar" then stops

      expect(client).to have_received(:chat_appendStream).with(
        hash_including(markdown_text: "bar"),
      )
      expect(client).to have_received(:chat_stopStream).with(
        hash_including(channel: "C1", ts: "999.1", markdown_text: "done"),
      )
    end

    it "is idempotent" do
      streamer.append_text("foo")
      streamer.stop
      streamer.stop

      expect(client).to have_received(:chat_stopStream).once
    end
  end

  describe "degradation" do
    before do
      allow(client).to receive(:chat_startStream).and_raise(StandardError, "streaming unavailable")
    end

    it "falls back to postMessage with the accumulated text when startStream fails" do
      streamer.append_text("hello ")
      streamer.append_text("world")
      streamer.stop

      expect(client).not_to have_received(:chat_appendStream)
      expect(client).to have_received(:chat_postMessage).with(
        hash_including(channel: "C1", thread_ts: "111.1", markdown_text: "hello world"),
      )
    end

    it "drops task labels entirely (they are ephemeral progress, not reply content)" do
      streamer.add_task("Preparing a goal form…")
      streamer.append_text("hello world")
      streamer.stop

      # The task label must not leak into the fallback message or post on its own.
      expect(client).not_to have_received(:post)
      expect(client).to have_received(:chat_postMessage).with(
        hash_including(markdown_text: "hello world"),
      )
    end

    it "posts nothing when the turn produced only task labels" do
      streamer.add_task("Preparing a goal form…")
      streamer.stop

      expect(client).not_to have_received(:chat_postMessage)
      expect(client).not_to have_received(:post)
    end

    it "sends the fallback as markdown_text (not the legacy text field) so GFM renders" do
      streamer.append_text("**bold** and\n\n| a | b |\n|---|---|\n| 1 | 2 |")
      streamer.stop

      payload = nil
      expect(client).to have_received(:chat_postMessage) { |kwargs| payload = kwargs }
      expect(payload[:markdown_text]).to eq("**bold** and\n\n| a | b |\n|---|---|\n| 1 | 2 |")
      expect(payload).not_to have_key(:text)
    end

    it "truncates the fallback to Slack's markdown_text limit" do
      streamer.append_text("x" * 20_000)
      streamer.stop

      payload = nil
      expect(client).to have_received(:chat_postMessage) { |kwargs| payload = kwargs }
      expect(payload[:markdown_text].length).to be <= Slack::Streamer::MARKDOWN_MAX_CHARS
    end
  end

  describe "#set_status" do
    it "calls setStatus and swallows errors (status is decoration)" do
      allow(client).to receive(:assistant_threads_setStatus).and_raise(StandardError, "no scope")

      expect { streamer.set_status("is thinking…") }.not_to raise_error
      expect(client).to have_received(:assistant_threads_setStatus).with(
        hash_including(channel_id: "C1", thread_ts: "111.1", status: "is thinking…"),
      )
    end

    it "clears the status with an empty string" do
      streamer.clear_status

      expect(client).to have_received(:assistant_threads_setStatus).with(
        hash_including(status: ""),
      )
    end
  end
end
