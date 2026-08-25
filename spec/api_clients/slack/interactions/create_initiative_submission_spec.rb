require "rails_helper"

RSpec.describe Slack::Interactions::CreateInitiativeSubmission do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:creator) { create(:user, organization: organization, provider_uid: "U_CREATOR") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) { create(:goal, organization: organization, title: "Grow activation") }
  let(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "C_AGENT", slack_thread_ts: "8.8",
                          surface: "channel")
  end

  def payload(values_overrides = {})
    values = {
      "goal_block" => { "goal" => { "selected_option" => { "value" => goal.id.to_s } } },
      "title_block" => { "title" => { "value" => "Ship onboarding revamp" } },
      "description_block" => { "description" => { "value" => "desc" } },
      "owner_block" => { "owner" => { "selected_user" => owner.provider_uid } }
    }.deep_merge(values_overrides)

    {
      "type" => "view_submission",
      "team" => { "id" => "T1" },
      "user" => { "id" => creator.provider_uid },
      "view" => {
        "callback_id" => "create_initiative",
        "private_metadata" => { agent_run_id: agent_run.id }.to_json,
        "state" => { "values" => values }
      }
    }
  end

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(
      instance_double(Slack::Request::SendMessage, send_message: nil)
    )
  end

  context "when the run is still paused on show_initiative_create_form" do
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "show_initiative_create_form" })
    end

    it "creates the Initiative, posts InitiativeDisplay, and clears the modal" do
      sender = instance_double(Slack::Request::SendMessage)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_message) do |channel, message|
        expect(channel).to eq("C_AGENT")
        expect(message[:thread_ts]).to eq("8.8")
        expect(message[:attachments].first[:blocks].to_s).to include("Ship onboarding revamp")
      end

      result = described_class.new(payload).call

      expect(result).to eq(response_action: "clear")

      initiative = Initiative.sole
      expect(initiative.title).to eq("Ship onboarding revamp")
      expect(initiative.description).to eq("desc")
      expect(initiative.goal).to eq(goal)
      expect(initiative.owner).to eq(owner)
      expect(initiative).to be_status_proposed
    end

    it "returns an inline error and creates nothing when no goal is selected" do
      result = described_class.new(
        payload("goal_block" => { "goal" => { "selected_option" => nil } })
      ).call

      expect(result).to eq(response_action: "errors", errors: { "goal_block" => "Please select a goal" })
      expect(Initiative.count).to eq(0)
    end

    it "returns an inline error and creates nothing when the goal can't take new initiatives" do
      goal.update!(status: "completed")

      result = described_class.new(payload).call

      expect(result).to eq(
        response_action: "errors", errors: { "goal_block" => "That goal can't take new initiatives right now" }
      )
      expect(Initiative.count).to eq(0)
    end

    it "returns an inline error and creates nothing when the title is blank" do
      result = described_class.new(
        payload("title_block" => { "title" => { "value" => "" } })
      ).call

      expect(result).to eq(response_action: "errors", errors: { "title_block" => "Please enter a title" })
      expect(Initiative.count).to eq(0)
    end

    it "returns an inline error and creates nothing when no owner is selected" do
      result = described_class.new(
        payload("owner_block" => { "owner" => { "selected_user" => nil } })
      ).call

      expect(result).to eq(response_action: "errors", errors: { "owner_block" => "Please select an owner" })
      expect(Initiative.count).to eq(0)
    end

    it "enqueues AgentResumeJob with a tool_result summarizing the created initiative" do
      expect do
        described_class.new(payload).call
      end.to have_enqueued_job(AgentResumeJob).with(
        hash_including(
          agent_run_id: agent_run.id,
          slack_user_id: creator.provider_uid,
          tool_result: hash_including(
            status: "created",
            initiative: hash_including(title: "Ship onboarding revamp", goal_id: goal.id, owner: owner.full_name),
          ),
        )
      )
    end

    it "stamps produced_initiative_id onto the run's pending_tool_call, preserving id/name/args" do
      described_class.new(payload).call

      expect(agent_run.reload.pending_tool_call).to include(
        "id" => "call_1", "name" => "show_initiative_create_form", "produced_initiative_id" => Initiative.sole.id
      )
    end
  end

  context "when the run has moved on (not paused, or paused on a different tool)" do
    let!(:agent_run) { create(:agent_run, conversation: conversation, status: "completed") }

    it "enqueues a late-submit AgentTurnJob event turn instead of AgentResumeJob" do
      expect do
        described_class.new(payload).call
      end.to have_enqueued_job(AgentTurnJob).with(
        hash_including(
          slack_team_id: workspace.identifier,
          channel: "C_AGENT",
          thread_ts: "8.8",
          surface: "channel",
          slack_user_id: creator.provider_uid,
          event: a_string_including("initiative 'Ship onboarding revamp' was created"),
        )
      )

      expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("AgentResumeJob")
    end
  end

  context "when the run already produced an initiative (replayed submission)" do
    let(:produced_initiative) { create(:initiative, goal: goal, title: "Ship onboarding revamp") }
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: {
          "id" => "call_1", "name" => "show_initiative_create_form", "produced_initiative_id" => produced_initiative.id
        })
    end

    it "creates no duplicate initiative, enqueues nothing, and updates the modal with the already-created info view" do
      expect do
        result = described_class.new(payload).call

        expect(result[:response_action]).to eq("update")
        expect(result[:view]).to be_a(Hash)
        text = result[:view][:blocks].sole[:text][:text]
        expect(text).to include("Ship onboarding revamp")
      end.not_to change(Initiative, :count)

      expect(enqueued_jobs).to be_empty
    end
  end
end
