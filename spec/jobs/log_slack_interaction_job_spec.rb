require "rails_helper"

RSpec.describe LogSlackInteractionJob do
  def run(**kwargs)
    described_class.perform_now(**kwargs)
  end

  describe "inbound" do
    it "records an Events API callback with identity fields and the resolved org" do
      org = create(:organization)
      create(:slack_workspace, organization: org, identifier: "T1")

      run(direction: "inbound", slack_params: {
        "type" => "event_callback",
        "team_id" => "T1",
        "event" => { "type" => "app_mention", "channel" => "C9", "ts" => "111.222",
                     "thread_ts" => "111.000", "user" => "U9", "text" => "hi" }
      })

      si = SlackInteraction.last
      expect(si).to have_attributes(
        direction: "inbound", event_type: "app_mention", team_id: "T1",
        channel_id: "C9", ts: "111.222", thread_ts: "111.000",
        slack_user_id: "U9", organization_id: org.id,
      )
      expect(si.payload.dig("event", "text")).to eq("hi")
    end

    it "normalises a root message's thread_ts to its own ts for thread grouping" do
      # A root/un-threaded message has no thread_ts; the bot's reply is posted with
      # thread_ts = the root ts, so the root row must share that thread_ts or
      # in_thread would miss the message that started the conversation.
      run(direction: "inbound", slack_params: {
        "type" => "event_callback", "team_id" => "T1",
        "event" => { "type" => "app_mention", "channel" => "C9", "ts" => "111.222", "user" => "U9" }
      })
      run(direction: "outbound", api_method: "chat.postMessage", team_id: "T1",
        request_payload: { "channel" => "C9", "thread_ts" => "111.222", "text" => "reply" },
        response: { "ok" => true, "channel" => "C9", "ts" => "111.999" }, ok: true)

      expect(SlackInteraction.in_thread("C9", "111.222").map(&:direction))
        .to eq([ "inbound", "outbound" ])
    end

    it "parses an interactive payload and pulls identity from container/team/user" do
      create(:slack_workspace, identifier: "T2")
      payload = {
        type: "block_actions",
        team: { id: "T2" }, user: { id: "U2" },
        container: { channel_id: "C2", message_ts: "200.1" },
        actions: [ { action_id: "open_create_goal_modal", value: "1" } ]
      }.to_json

      run(direction: "inbound", slack_params: { "payload" => payload })

      expect(SlackInteraction.last).to have_attributes(
        event_type: "block_actions", team_id: "T2",
        channel_id: "C2", ts: "200.1", slack_user_id: "U2",
      )
      expect(SlackInteraction.last.payload.dig("actions", 0, "action_id"))
        .to eq("open_create_goal_modal")
    end

    it "records a view_submission" do
      payload = {
        type: "view_submission",
        team: { id: "T3" }, user: { id: "U3" },
        view: { callback_id: "CreateGoalModal" }
      }.to_json

      run(direction: "inbound", slack_params: { "payload" => payload })

      expect(SlackInteraction.last).to have_attributes(
        event_type: "view_submission", team_id: "T3", slack_user_id: "U3",
      )
    end

    it "records url_verification with no organization" do
      run(direction: "inbound", slack_params: { "type" => "url_verification", "challenge" => "x" })

      expect(SlackInteraction.last).to have_attributes(
        event_type: "url_verification", team_id: nil, organization_id: nil,
      )
    end

    it "captures Slack retry metadata when present" do
      run(direction: "inbound",
        slack_params: { "type" => "event_callback", "event" => { "type" => "app_mention" } },
        retry_num: "2", retry_reason: "http_timeout")

      expect(SlackInteraction.last).to have_attributes(retry_num: 2, retry_reason: "http_timeout")
    end

    it "does not raise on a malformed interactive payload" do
      expect do
        run(direction: "inbound", slack_params: { "payload" => "not json" })
      end.to change(SlackInteraction, :count).by(1)
    end
  end

  describe "outbound" do
    it "records a conversational call and captures the response ts" do
      org = create(:organization)
      create(:slack_workspace, organization: org, identifier: "T4")

      run(direction: "outbound", api_method: "chat.postMessage", team_id: "T4",
        request_payload: { "channel" => "C4", "thread_ts" => "400.0", "text" => "hi" },
        response: { "ok" => true, "channel" => "C4", "ts" => "400.9" }, ok: true)

      si = SlackInteraction.last
      expect(si).to have_attributes(
        direction: "outbound", event_type: "chat.postMessage", team_id: "T4",
        channel_id: "C4", ts: "400.9", thread_ts: "400.0", ok: true,
        organization_id: org.id,
      )
      expect(si.response["ts"]).to eq("400.9")
    end

    it "records a failed outbound call with the error and ok: false" do
      run(direction: "outbound", api_method: "views.open", team_id: "T4",
        request_payload: { "trigger_id" => "tg" }, ok: false, error: "expired_trigger_id")

      expect(SlackInteraction.last).to have_attributes(
        direction: "outbound", event_type: "views.open", ok: false, error: "expired_trigger_id",
      )
    end
  end
end
