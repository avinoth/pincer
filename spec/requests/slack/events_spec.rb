require "rails_helper"

RSpec.describe "Slack::Events", type: :request do
  let(:signing_secret) { "test_signing_secret" }

  around do |example|
    original = ENV["SLACK_SIGNING_SECRET"]
    ENV["SLACK_SIGNING_SECRET"] = signing_secret
    example.run
    ENV["SLACK_SIGNING_SECRET"] = original
  end

  def signed_headers(body, timestamp: Time.now.to_i, secret: signing_secret)
    basestring = "v0:#{timestamp}:#{body}"
    signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, basestring)}"
    {
      "X-Slack-Request-Timestamp" => timestamp.to_s,
      "X-Slack-Signature" => signature,
      "CONTENT_TYPE" => "application/json"
    }
  end

  describe "POST /slack/events" do
    it "answers the url_verification challenge when signed correctly" do
      body = { type: "url_verification", challenge: "chal-123" }.to_json

      post "/slack/events", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["challenge"]).to eq("chal-123")
    end

    it "rejects a bad signature" do
      body = { type: "url_verification", challenge: "chal-123" }.to_json
      headers = signed_headers(body).merge("X-Slack-Signature" => "v0=deadbeef")

      post "/slack/events", params: body, headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a stale (replayed) timestamp" do
      body = { type: "url_verification", challenge: "x" }.to_json
      headers = signed_headers(body, timestamp: 10.minutes.ago.to_i)

      post "/slack/events", params: body, headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "enqueues the interaction logger for every verified inbound request" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "app_mention", channel: "C1", ts: "1.2", user: "U1", text: "<@U0BOT> hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(LogSlackInteractionJob).with(hash_including(direction: "inbound"))
      expect(response).to have_http_status(:ok)
    end

    it "does not log a request that fails signature verification" do
      body = { type: "url_verification", challenge: "x" }.to_json
      headers = signed_headers(body).merge("X-Slack-Signature" => "v0=deadbeef")

      expect do
        post "/slack/events", params: body, headers: headers
      end.not_to have_enqueued_job(LogSlackInteractionJob)
      expect(response).to have_http_status(:unauthorized)
    end

    it "marks the organization inactive on app_uninstalled" do
      organization = create(:organization, status: :active)
      workspace = create(:slack_workspace, organization: organization)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "app_uninstalled" }
      }.to_json

      post "/slack/events", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(organization.reload).to be_inactive
    end

    it "enqueues an agent turn for an app_mention, with the bot mention cleaned out of the text" do
      workspace = create(:slack_workspace, bot_uid: "U0BOT")
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "app_mention", channel: "C1", ts: "1.2", user: "U1", text: "<@U0BOT> hi there" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(AgentTurnJob).with(
        hash_including(
          slack_team_id: workspace.identifier, channel: "C1", thread_ts: "1.2",
          surface: "channel", slack_user_id: "U1", text: "@pincer hi there",
        )
      )
      expect(response).to have_http_status(:ok)
    end

    it "does not enqueue an agent turn for a bot's own app_mention (loop guard)" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "app_mention", channel: "C1", ts: "1.2", bot_id: "B1", text: "hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.not_to have_enqueued_job(AgentTurnJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues the team-join sync job with the full user payload" do
      workspace = create(:slack_workspace)
      slack_user_payload = { id: "U9", team_id: workspace.identifier, real_name: "New Person",
        profile: { email: "new@example.com" } }
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "team_join", user: slack_user_payload }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(ProcessTeamJoinJob).with(
        hash_including(team_id: workspace.identifier, user: hash_including("id" => "U9"))
      )
      expect(response).to have_http_status(:ok)
    end

    it "does not enqueue team-join sync when the payload has no user" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "team_join" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.not_to have_enqueued_job(ProcessTeamJoinJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues an agent turn (dm surface) for a 1:1 direct message with no prior conversation" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "message", channel_type: "im", channel: "D1", ts: "1.2", user: "U1", text: "grow signups" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(AgentTurnJob).with(
        hash_including(
          slack_team_id: workspace.identifier, channel: "D1", thread_ts: "1.2",
          surface: "dm", slack_user_id: "U1", text: "grow signups",
        )
      )
      expect(response).to have_http_status(:ok)
    end

    it "enqueues an agent turn (assistant surface) for a message.im carrying an assistant_thread marker" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: {
          type: "message", channel_type: "im", channel: "D1", ts: "1.2", user: "U1", text: "hi",
          assistant_thread: { channel_id: "D1", thread_ts: "1.2" }
        }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(AgentTurnJob).with(hash_including(surface: "assistant"))
      expect(response).to have_http_status(:ok)
    end

    it "reuses the existing Conversation's surface for a message.im in a known assistant thread" do
      workspace = create(:slack_workspace)
      organization = workspace.organization
      create(:conversation, organization: organization, slack_channel_id: "D1", slack_thread_ts: "1.2", surface: "assistant")
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "message", channel_type: "im", channel: "D1", ts: "1.2", user: "U1", text: "hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(AgentTurnJob).with(hash_including(surface: "assistant"))
      expect(response).to have_http_status(:ok)
    end

    it "does not enqueue for a channel message" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "message", channel_type: "channel", channel: "C1", ts: "1.2", user: "U1", text: "hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.not_to have_enqueued_job(AgentTurnJob)
      expect(response).to have_http_status(:ok)
    end

    it "does not enqueue for a group DM (mpim) message" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "message", channel_type: "mpim", channel: "G1", ts: "1.2", user: "U1", text: "hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.not_to have_enqueued_job(AgentTurnJob)
      expect(response).to have_http_status(:ok)
    end

    it "ignores a DM from a bot (loop guard)" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "message", channel_type: "im", channel: "D1", ts: "1.2", bot_id: "B1", text: "hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.not_to have_enqueued_job(AgentTurnJob)
      expect(response).to have_http_status(:ok)
    end

    it "ignores a DM with a subtype (edits/system messages)" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: { type: "message", channel_type: "im", subtype: "message_changed", channel: "D1", ts: "1.2", user: "U1", text: "hi" }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.not_to have_enqueued_job(AgentTurnJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues AssistantThreadStartedJob for assistant_thread_started" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: {
          type: "assistant_thread_started",
          assistant_thread: {
            user_id: "U1", channel_id: "D1", thread_ts: "1.2",
            context: { channel_id: "C9" }
          }
        }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(AssistantThreadStartedJob).with(
        hash_including(
          slack_team_id: workspace.identifier, channel: "D1", thread_ts: "1.2", slack_user_id: "U1",
          context: hash_including("channel_id" => "C9"),
        )
      )
      expect(response).to have_http_status(:ok)
    end

    it "enqueues AssistantThreadContextChangedJob for assistant_thread_context_changed" do
      workspace = create(:slack_workspace)
      body = {
        type: "event_callback",
        team_id: workspace.identifier,
        event: {
          type: "assistant_thread_context_changed",
          assistant_thread: {
            channel_id: "D1", thread_ts: "1.2",
            context: { channel_id: "C9" }
          }
        }
      }.to_json

      expect do
        post "/slack/events", params: body, headers: signed_headers(body)
      end.to have_enqueued_job(AssistantThreadContextChangedJob).with(
        hash_including(
          slack_team_id: workspace.identifier, channel: "D1", thread_ts: "1.2",
          context: hash_including("channel_id" => "C9"),
        )
      )
      expect(response).to have_http_status(:ok)
    end

    it "routes an interactive payload (button click) posted to this URL" do
      organization = create(:organization)
      create(:slack_workspace, organization: organization, identifier: "T1")
      conversation = create(:conversation, organization: organization)
      agent_run = create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form", "args" => { "title" => "Grow activation" } })

      open_view = instance_double(Slack::Request::OpenView, open_modal: nil)
      allow(Slack::Request::OpenView).to receive(:new).and_return(open_view)

      payload = {
        type: "block_actions",
        team: { id: "T1" },
        user: { id: "U1" },
        trigger_id: "trigger-123",
        actions: [ { action_id: "agent_open_create_goal_modal", value: agent_run.id.to_s } ]
      }.to_json
      body = "payload=#{CGI.escape(payload)}"
      headers = signed_headers(body).merge("CONTENT_TYPE" => "application/x-www-form-urlencoded")

      post "/slack/events", params: body, headers: headers

      expect(response).to have_http_status(:ok)
      expect(open_view).to have_received(:open_modal)
    end
  end
end
