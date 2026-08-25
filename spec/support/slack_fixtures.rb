# Load the hand-captured Slack payloads under spec/fixtures/slack and wrap them
# in the response objects the app uses, so specs stub at the Slack::Request::*
# boundary with realistic response shapes.
module SlackFixtures
  def slack_payload(name)
    JSON.parse(File.read(Rails.root.join("spec/fixtures/slack/#{name}.json")))
  end

  def slack_auth_response
    Slack::Response::Auth.new(slack_payload("auth"))
  end

  def slack_user_response
    Slack::Response::User.new(slack_payload("user_by_id"))
  end

  def slack_user_list_response(payload = slack_payload("users_list"))
    Slack::Response::UserList.new(payload)
  end
end

RSpec.configure do |config|
  config.include SlackFixtures
end
