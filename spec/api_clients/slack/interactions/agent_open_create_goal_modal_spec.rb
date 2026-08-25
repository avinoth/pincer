require "rails_helper"

RSpec.describe Slack::Interactions::AgentOpenCreateGoalModal do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "C1", slack_thread_ts: "9.9")
  end
  let(:agent_run) do
    create(:agent_run, conversation: conversation, status: "paused_on_tool",
      pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form", "args" => { "title" => "Grow activation" } })
  end

  let(:open_view) { instance_double(Slack::Request::OpenView, open_modal: nil) }

  before { allow(Slack::Request::OpenView).to receive(:new).and_return(open_view) }

  def payload(value:)
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => "U1" },
      "trigger_id" => "trigger-123",
      "actions" => [ { "action_id" => "agent_open_create_goal_modal", "value" => value } ]
    }
  end

  it "opens a Create Goal modal prefilled from the run's pending tool call, with the click's trigger_id" do
    described_class.new(payload(value: agent_run.id.to_s)).call

    expect(open_view).to have_received(:open_modal) do |view, trigger_id|
      expect(trigger_id).to eq("trigger-123")
      expect(view).to be_a(Slack::Views::CreateGoalModal)
      expect(JSON.parse(view.private_metadata)).to eq("agent_run_id" => agent_run.id)

      title_block = view.to_h[:blocks].find { |b| b[:block_id] == "title_block" }
      expect(title_block[:element][:initial_value]).to eq("Grow activation")
    end
  end

  it "does nothing when the referenced run is missing" do
    described_class.new(payload(value: "0")).call
    expect(open_view).not_to have_received(:open_modal)
  end

  context "when the run's pending_tool_call already carries a produced_goal_id" do
    let(:creator) { create(:user, organization: organization, full_name: "Jamie Rivera") }
    let(:goal) do
      create(:goal, organization: organization, creator: creator, title: "Grow activation",
        start_date: "2026-08-01", end_date: "2026-09-01")
    end
    let(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form", "produced_goal_id" => goal.id })
    end

    it "opens the GoalAlreadyCreatedModal info view instead of the editable Create Goal form" do
      described_class.new(payload(value: agent_run.id.to_s)).call

      expect(open_view).to have_received(:open_modal) do |view, trigger_id|
        expect(trigger_id).to eq("trigger-123")
        expect(view).to be_a(Slack::Views::GoalAlreadyCreatedModal)

        text = view.to_h[:blocks].sole[:text][:text]
        expect(text).to include("Grow activation")
        expect(text).to include("Jamie Rivera")
      end
    end

    it "falls back to generic copy when the referenced goal has been deleted" do
      agent_run # eager-load before destroying the goal it points at
      goal.destroy!

      described_class.new(payload(value: agent_run.id.to_s)).call

      expect(open_view).to have_received(:open_modal) do |view, _trigger_id|
        expect(view).to be_a(Slack::Views::GoalAlreadyCreatedModal)
        expect(view.to_h[:blocks].sole[:text][:text]).to eq("This goal was already created.")
      end
    end
  end

  it "does nothing when the run belongs to a different organization" do
    other_org = create(:organization)
    create(:slack_workspace, organization: other_org)
    other_conversation = create(:conversation, organization: other_org)
    other_run = create(:agent_run, conversation: other_conversation, status: "paused_on_tool")

    described_class.new(payload(value: other_run.id.to_s)).call
    expect(open_view).not_to have_received(:open_modal)
  end
end
