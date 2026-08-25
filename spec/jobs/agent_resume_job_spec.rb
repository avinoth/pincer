require "rails_helper"

RSpec.describe AgentResumeJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let!(:author) { create(:user, organization: organization, provider_uid: "U_AUTHOR") }
  let(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "C1",
                          slack_thread_ts: "1700000000.000100", surface: "channel")
  end
  let(:tool_result) { { status: "created", goal: { id: 42, title: "Grow activation" } } }

  def perform(agent_run_id:, slack_user_id: "U_AUTHOR")
    described_class.new.perform(agent_run_id: agent_run_id, tool_result: tool_result, slack_user_id: slack_user_id)
  end

  context "when the run is still paused" do
    let!(:run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
                         pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form" })
    end

    it "resumes the run with the given tool result" do
      allow(Ai::Agent::Resume).to receive(:call)

      perform(agent_run_id: run.id)

      expect(Ai::Agent::Resume).to have_received(:call)
        .with(agent_run: run, tool_result: tool_result, recipient_user_id: "U_AUTHOR")
    end
  end

  context "when the run is no longer paused (resolve-once superseded it while queued)" do
    let!(:run) { create(:agent_run, conversation: conversation, status: "completed") }

    it "falls back to enqueuing a late-submit event turn instead of raising" do
      expect do
        perform(agent_run_id: run.id)
      end.to have_enqueued_job(AgentTurnJob).with(
        hash_including(
          slack_team_id: workspace.identifier,
          channel: "C1",
          thread_ts: "1700000000.000100",
          surface: "channel",
          slack_user_id: "U_AUTHOR",
          event: a_string_including("goal 'Grow activation' was created (id 42)"),
        )
      )
    end
  end

  it "does nothing when the run can't be found" do
    expect { perform(agent_run_id: 0) }.not_to have_enqueued_job(AgentTurnJob)
  end
end
