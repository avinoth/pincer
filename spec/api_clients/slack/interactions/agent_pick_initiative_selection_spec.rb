require "rails_helper"

RSpec.describe Slack::Interactions::AgentPickInitiativeSelection do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "C_AGENT", slack_thread_ts: "8.8",
                          surface: "channel")
  end
  let(:picker) { create(:user, organization: organization, provider_uid: "U_PICKER") }
  let(:goal) { create(:goal, organization: organization) }
  let(:initiative) { create(:initiative, goal: goal, title: "Ship onboarding revamp") }

  def payload(block_id:, selected_value:)
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => picker.provider_uid },
      "channel" => { "id" => "C_AGENT" },
      "actions" => [
        {
          "action_id" => "agent_pick_initiative",
          "block_id" => block_id,
          "type" => "static_select",
          "selected_option" => { "text" => { "type" => "plain_text", "text" => initiative.title }, "value" => selected_value }
        }
      ]
    }
  end

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(
      instance_double(Slack::Request::SendMessage, send_message: nil, send_ephemeral: nil)
    )
  end

  context "when the run is paused on pick_initiative" do
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: {
          "id" => "call_1", "name" => "pick_initiative", "args" => { "candidate_initiative_ids" => [ initiative.id ] }
        })
    end

    it "enqueues AgentResumeJob with the chosen initiative summary" do
      expect do
        described_class.new(payload(block_id: "agent_pick_initiative_#{agent_run.id}", selected_value: initiative.id.to_s)).call
      end.to have_enqueued_job(AgentResumeJob).with(
        hash_including(
          agent_run_id: agent_run.id,
          slack_user_id: picker.provider_uid,
          tool_result: hash_including(id: initiative.id, title: "Ship onboarding revamp"),
        )
      )
    end

    it "stamps produced_initiative_id onto the run's pending_tool_call, preserving id/name/args" do
      described_class.new(payload(block_id: "agent_pick_initiative_#{agent_run.id}", selected_value: initiative.id.to_s)).call

      expect(agent_run.reload.pending_tool_call).to include(
        "id" => "call_1", "name" => "pick_initiative", "produced_initiative_id" => initiative.id
      )
      expect(agent_run.reload.pending_tool_call["args"]).to eq("candidate_initiative_ids" => [ initiative.id ])
    end

    it "does nothing when the selected initiative doesn't exist in this organization" do
      foreign_initiative = create(:initiative)

      expect do
        described_class.new(
          payload(block_id: "agent_pick_initiative_#{agent_run.id}", selected_value: foreign_initiative.id.to_s)
        ).call
      end.not_to have_enqueued_job(AgentResumeJob)

      expect(agent_run.reload.pending_tool_call).not_to have_key("produced_initiative_id")
    end

    it "does nothing when the run id in the block_id doesn't resolve" do
      expect do
        described_class.new(payload(block_id: "agent_pick_initiative_999999999", selected_value: initiative.id.to_s)).call
      end.not_to have_enqueued_job(AgentResumeJob)
    end
  end

  context "when the run has moved on (not paused, or paused on a different tool)" do
    let!(:agent_run) { create(:agent_run, conversation: conversation, status: "completed") }

    it "enqueues a late-submit AgentTurnJob event turn instead of AgentResumeJob" do
      expect do
        described_class.new(payload(block_id: "agent_pick_initiative_#{agent_run.id}", selected_value: initiative.id.to_s)).call
      end.to have_enqueued_job(AgentTurnJob).with(
        hash_including(
          slack_team_id: workspace.identifier,
          channel: "C_AGENT",
          thread_ts: "8.8",
          surface: "channel",
          slack_user_id: picker.provider_uid,
          event: a_string_including("Ship onboarding revamp"),
        )
      )

      expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("AgentResumeJob")
    end
  end

  context "when the run already produced an initiative (replayed selection)" do
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "pick_initiative", "produced_initiative_id" => initiative.id })
    end

    it "enqueues nothing and tells the acting user it was already picked" do
      sender = instance_double(Slack::Request::SendMessage, send_ephemeral: nil)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_ephemeral).with("C_AGENT", picker.provider_uid, { text: "This initiative was already picked." })

      expect do
        described_class.new(payload(block_id: "agent_pick_initiative_#{agent_run.id}", selected_value: initiative.id.to_s)).call
      end.not_to have_enqueued_job(AgentResumeJob)

      expect(enqueued_jobs).to be_empty
    end
  end
end
