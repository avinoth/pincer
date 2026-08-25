require "rails_helper"

RSpec.describe "Slack::Interactions", type: :request do
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
      "CONTENT_TYPE" => "application/x-www-form-urlencoded"
    }
  end

  def form_body(payload_hash)
    "payload=#{CGI.escape(payload_hash.to_json)}"
  end

  it "routes a signed block_actions payload and acks" do
    handler = instance_double(Slack::Interactions::Wave, call: nil)
    allow(Slack::Interactions::Wave).to receive(:new).and_return(handler)

    body = form_body(type: "block_actions", actions: [ { action_id: "wave" } ])
    post "/slack/interactions", params: body, headers: signed_headers(body)

    expect(response).to have_http_status(:ok)
    expect(Slack::Interactions::Wave).to have_received(:new)
  end

  it "returns a response_action for a view_submission" do
    body = form_body(
      type: "view_submission",
      view: { callback_id: "example", state: { values: {} } },
    )
    post "/slack/interactions", params: body, headers: signed_headers(body)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["response_action"]).to eq("errors")
  end

  it "rejects a bad signature" do
    body = form_body(type: "block_actions", actions: [])
    headers = signed_headers(body).merge("X-Slack-Signature" => "v0=deadbeef")
    post "/slack/interactions", params: body, headers: headers

    expect(response).to have_http_status(:unauthorized)
  end
end
