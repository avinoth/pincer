require "rails_helper"

RSpec.describe Slack::Interactions::AgentConfirmDeleteInitiative do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "C_AGENT", slack_thread_ts: "8.8", surface: "channel")
  end
  let(:goal) { create(:goal, organization: organization) }
  let(:clicker) { create(:user, organization: organization, provider_uid: "U_CLICKER") }

  def payload(value:, user_id: clicker.provider_uid)
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "channel" => { "id" => "C_AGENT" },
      "container" => { "message_ts" => "111.222" },
      "actions" => [ { "action_id" => "agent_confirm_delete_initiative", "value" => value } ]
    }
  end

  before do
    allow(Slack::Request::UpdateMessage).to receive(:new).and_return(
      instance_double(Slack::Request::UpdateMessage, update_message: nil)
    )
    allow(Slack::Request::SendMessage).to receive(:new).and_return(
      instance_double(Slack::Request::SendMessage, send_ephemeral: nil, send_message: nil)
    )
  end

  context "when the run is paused on delete_initiative and the clicker is authorized" do
    let(:owner) { create(:user, organization: organization, provider_uid: "U_INIT_OWNER") }
    let!(:initiative) { create(:initiative, goal: goal, owner: owner, title: "Ship onboarding revamp") }
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "delete_initiative", "args" => { "initiative_id" => initiative.id } })
    end

    it "deletes the initiative and enqueues AgentResumeJob with a deleted-status tool result" do
      expect do
        described_class.new(payload(value: agent_run.id.to_s, user_id: owner.provider_uid)).call
      end.to have_enqueued_job(AgentResumeJob).with(
        hash_including(
          agent_run_id: agent_run.id,
          slack_user_id: owner.provider_uid,
          tool_result: hash_including(
            status: "deleted",
            initiative: hash_including(id: initiative.id, title: "Ship onboarding revamp"),
          ),
        )
      )

      expect(Initiative.exists?(initiative.id)).to be false
    end

    it "stamps deleted_initiative_id onto the run's pending_tool_call, preserving id/name/args" do
      described_class.new(payload(value: agent_run.id.to_s, user_id: owner.provider_uid)).call

      pending = agent_run.reload.pending_tool_call
      expect(pending).to include("id" => "call_1", "name" => "delete_initiative", "deleted_initiative_id" => initiative.id)
      expect(pending["args"]).to eq("initiative_id" => initiative.id)
    end

    it "replaces the origin prompt message with a tombstone" do
      updater = instance_double(Slack::Request::UpdateMessage)
      allow(Slack::Request::UpdateMessage).to receive(:new).with(workspace).and_return(updater)
      expect(updater).to receive(:update_message).with("C_AGENT", "111.222", hash_including(text: a_string_including("deleted")))

      described_class.new(payload(value: agent_run.id.to_s, user_id: owner.provider_uid)).call
    end

    it "allows the goal's owners/creator (not just the initiative's own owner) to confirm" do
      creator = goal.creator

      expect do
        described_class.new(payload(value: agent_run.id.to_s, user_id: creator.provider_uid)).call
      end.to have_enqueued_job(AgentResumeJob)

      expect(Initiative.exists?(initiative.id)).to be false
    end
  end

  context "when the clicker is not authorized to delete the initiative" do
    let(:owner) { create(:user, organization: organization, provider_uid: "U_INIT_OWNER") }
    let!(:initiative) { create(:initiative, goal: goal, owner: owner, title: "Ship onboarding revamp") }
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "delete_initiative", "args" => { "initiative_id" => initiative.id } })
    end

    it "refuses with an ephemeral message and does not delete or resume" do
      sender = instance_double(Slack::Request::SendMessage, send_ephemeral: nil)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_ephemeral).with(
        "C_AGENT", "U_CLICKER", { text: "Only the initiative's owner or the goal's owners/creator can delete it." }
      )

      expect do
        described_class.new(payload(value: agent_run.id.to_s)).call
      end.not_to have_enqueued_job(AgentResumeJob)

      expect(Initiative.exists?(initiative.id)).to be true
      expect(agent_run.reload.pending_tool_call).not_to have_key("deleted_initiative_id")
    end
  end

  context "when the run has moved on (not paused, or paused on a different tool)" do
    let(:owner) { create(:user, organization: organization, provider_uid: "U_INIT_OWNER") }
    let!(:initiative) { create(:initiative, goal: goal, owner: owner, title: "Ship onboarding revamp") }
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "completed",
        pending_tool_call: { "id" => "call_1", "name" => "delete_initiative", "args" => { "initiative_id" => initiative.id } })
    end

    it "still deletes, but narrates a late AgentTurnJob event instead of resuming" do
      expect do
        described_class.new(payload(value: agent_run.id.to_s, user_id: owner.provider_uid)).call
      end.to have_enqueued_job(AgentTurnJob).with(
        hash_including(
          slack_team_id: workspace.identifier,
          channel: "C_AGENT",
          thread_ts: "8.8",
          surface: "channel",
          slack_user_id: owner.provider_uid,
          event: a_string_including("Ship onboarding revamp"),
        )
      )

      expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("AgentResumeJob")
      expect(Initiative.exists?(initiative.id)).to be false
    end
  end

  context "when the run already produced a deleted_initiative_id (replayed confirm)" do
    let(:owner) { create(:user, organization: organization, provider_uid: "U_INIT_OWNER") }
    let!(:initiative) { create(:initiative, goal: goal, owner: owner, title: "Ship onboarding revamp") }
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "delete_initiative", "deleted_initiative_id" => initiative.id })
    end

    it "does nothing further and tells the acting user it was already deleted" do
      sender = instance_double(Slack::Request::SendMessage, send_ephemeral: nil)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_ephemeral).with("C_AGENT", "U_CLICKER", { text: "This initiative was already deleted." })

      expect do
        described_class.new(payload(value: agent_run.id.to_s)).call
      end.not_to have_enqueued_job(AgentResumeJob)

      expect(enqueued_jobs).to be_empty
      expect(Slack::Request::UpdateMessage).not_to have_received(:new)
    end
  end

  context "when the initiative referenced by the run is already gone" do
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "delete_initiative", "args" => { "initiative_id" => 999_999_999 } })
    end

    it "treats it as already deleted: stamps the run, tombstones the prompt, and resumes with an already_deleted result" do
      expect do
        described_class.new(payload(value: agent_run.id.to_s)).call
      end.to have_enqueued_job(AgentResumeJob).with(
        hash_including(tool_result: hash_including(status: "already_deleted"))
      )

      expect(agent_run.reload.pending_tool_call["deleted_initiative_id"]).to eq(999_999_999)
    end
  end

  it "does nothing when the run id doesn't resolve" do
    expect do
      described_class.new(payload(value: "999999999")).call
    end.not_to have_enqueued_job(AgentResumeJob)
  end

  it "does not resolve an agent run belonging to another organization" do
    other_org_conversation = create(:conversation)
    foreign_run = create(:agent_run, conversation: other_org_conversation, status: "paused_on_tool",
      pending_tool_call: { "id" => "call_1", "name" => "delete_initiative", "args" => { "initiative_id" => 1 } })

    expect do
      described_class.new(payload(value: foreign_run.id.to_s)).call
    end.not_to have_enqueued_job(AgentResumeJob)
  end
end
