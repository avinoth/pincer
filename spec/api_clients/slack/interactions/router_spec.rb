require "rails_helper"

RSpec.describe Slack::Interactions::Router do
  it "routes block_actions to the handler matching action_id" do
    handler = instance_double(Slack::Interactions::Wave, call: nil)
    allow(Slack::Interactions::Wave).to receive(:new).and_return(handler)

    payload = { "type" => "block_actions", "actions" => [ { "action_id" => "wave" } ] }
    described_class.new(payload).route

    expect(Slack::Interactions::Wave).to have_received(:new)
    expect(handler).to have_received(:call)
  end

  it "routes view_submission by callback_id and returns its response_action" do
    payload = {
      "type" => "view_submission",
      "view" => { "callback_id" => "example", "state" => { "values" => {} } }
    }

    result = described_class.new(payload).route

    expect(result).to include(response_action: "errors")
  end

  it "routes the summary card's View details action to ShowGoalDetail" do
    handler = instance_double(Slack::Interactions::ShowGoalDetail, call: nil)
    allow(Slack::Interactions::ShowGoalDetail).to receive(:new).and_return(handler)

    payload = {
      "type" => "block_actions",
      "actions" => [ { "action_id" => Slack::Messages::GoalSummaryList::VIEW_DETAIL_ACTION_ID } ]
    }
    described_class.new(payload).route

    expect(Slack::Interactions::ShowGoalDetail).to have_received(:new)
    expect(handler).to have_received(:call)
  end

  it "no-ops for an unregistered action_id" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => "nope" } ] }
    expect(described_class.new(payload).route).to be_nil
  end
end
