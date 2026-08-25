require "rails_helper"

RSpec.describe Slack::Interactions::CreateGoalSubmission do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:creator) { create(:user, organization: organization, provider_uid: "U_CREATOR") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:conversation) do
    create(:conversation, organization: organization, slack_channel_id: "C_AGENT", slack_thread_ts: "8.8",
                          surface: "channel")
  end

  def payload(values_overrides = {})
    values = {
      "title_block" => { "title" => { "value" => "Grow activation" } },
      "description_block" => { "description" => { "value" => "desc" } },
      "owners_block" => { "owners" => { "selected_users" => [ owner.provider_uid ] } },
      "start_date_block" => { "start_date" => { "selected_date" => "2026-08-01" } },
      "end_date_block" => { "end_date" => { "selected_date" => "2026-09-01" } },
      "name_block" => { "name" => { "value" => "Activation rate" } },
      "direction_block" => { "direction" => { "selected_option" => { "value" => "increase" } } },
      "start_value_block" => { "start_value" => { "value" => "20" } },
      "target_value_block" => { "target_value" => { "value" => "40" } },
      "unit_block" => { "unit" => { "value" => "%" } },
      "channel_block" => { "channel" => { "selected_conversation" => "C_PICKED" } },
      "summary_day_block" => { "summary_day" => { "selected_option" => { "value" => "5" } } },
      "summary_time_block" => { "summary_time" => { "selected_time" => "17:00" } }
    }.deep_merge(values_overrides)

    {
      "type" => "view_submission",
      "team" => { "id" => "T1" },
      "user" => { "id" => creator.provider_uid },
      "view" => {
        "callback_id" => "create_goal",
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

  context "when the run is still paused on show_goal_create_form" do
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form" })
    end

    it "creates the Goal and its Metric atomically in one submission, posts GoalDisplay, and clears the modal" do
      sender = instance_double(Slack::Request::SendMessage)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_message) do |channel, message|
        expect(channel).to eq("C_AGENT")
        expect(message[:thread_ts]).to eq("8.8")
        expect(message[:attachments].first[:blocks].to_s).to include("Grow activation")
      end

      result = described_class.new(payload).call

      expect(result).to eq(response_action: "clear")

      goal = Goal.sole
      expect(goal.title).to eq("Grow activation")
      expect(goal.description).to eq("desc")
      expect(goal.creator).to eq(creator)
      expect(goal.owners).to contain_exactly(owner)
      expect(goal.update_channel).to eq("C_PICKED")
      expect(goal).to be_publishing_published

      metric = goal.metric
      expect(metric.name).to eq("Activation rate")
      expect(metric.direction).to eq("increase")
      expect(metric.current_value).to eq(20)
      expect(metric.target_value).to eq(40)
      expect(metric.unit).to eq("%")
    end

    it "falls back to the run's conversation channel when no channel is picked" do
      result = described_class.new(
        payload("channel_block" => { "channel" => { "selected_conversation" => nil } })
      ).call

      expect(result).to eq(response_action: "clear")
      expect(Goal.sole.update_channel).to eq("C_AGENT")
    end

    describe "the Draft checkbox" do
      def draft_payload(checked:)
        payload(
          "draft_block" => {
            "draft" => { "selected_options" => (checked ? [ { "value" => "draft" } ] : []) }
          },
        )
      end

      it "saves a draft goal when checked" do
        result = described_class.new(draft_payload(checked: true)).call

        expect(result).to eq(response_action: "clear")
        expect(Goal.sole).to be_publishing_draft
      end

      it "publishes the goal when unchecked" do
        result = described_class.new(draft_payload(checked: false)).call

        expect(result).to eq(response_action: "clear")
        expect(Goal.sole).to be_publishing_published
      end
    end

    it "returns a single inline error and creates nothing when only one field is invalid" do
      result = described_class.new(
        payload("owners_block" => { "owners" => { "selected_users" => [] } })
      ).call

      expect(result).to eq(response_action: "errors", errors: { "owners_block" => "Pick at least one owner" })
      expect(Goal.count).to eq(0)
    end

    it "returns all goal-field and metric-field errors together in one response" do
      result = described_class.new(
        payload(
          "title_block" => { "title" => { "value" => "" } },
          "owners_block" => { "owners" => { "selected_users" => [] } },
          "name_block" => { "name" => { "value" => "" } },
          "target_value_block" => { "target_value" => { "value" => "" } },
        )
      ).call

      expect(result).to eq(
        response_action: "errors",
        errors: {
          "title_block" => "Please enter a goal title",
          "owners_block" => "Pick at least one owner",
          "name_block" => "Please name what to track",
          "target_value_block" => "Please set a target value"
        }
      )
      expect(Goal.count).to eq(0)
      expect(Metric.count).to eq(0)
    end

    it "returns an inline error when the end date is before the start date" do
      result = described_class.new(
        payload(
          "start_date_block" => { "start_date" => { "selected_date" => "2026-09-01" } },
          "end_date_block" => { "end_date" => { "selected_date" => "2026-08-01" } },
        )
      ).call

      expect(result).to eq(
        response_action: "errors", errors: { "end_date_block" => "End date can't be before the start date" }
      )
      expect(Goal.count).to eq(0)
    end

    it "returns an inline error and creates nothing when the metric name is missing" do
      result = described_class.new(
        payload("name_block" => { "name" => { "value" => "" } })
      ).call

      expect(result).to eq(response_action: "errors", errors: { "name_block" => "Please name what to track" })
      expect(Goal.count).to eq(0)
    end

    it "returns an inline error and creates nothing when the metric target value is missing" do
      result = described_class.new(
        payload("target_value_block" => { "target_value" => { "value" => "" } })
      ).call

      expect(result).to eq(response_action: "errors", errors: { "target_value_block" => "Please set a target value" })
      expect(Goal.count).to eq(0)
    end

    it "rolls back the whole transaction and returns an inline error when goal creation fails" do
      allow(CreateGoal).to receive(:call!).and_raise(Interactor::Failure.new)

      result = described_class.new(payload).call

      expect(result).to eq(
        response_action: "errors",
        errors: { "title_block" => "Something went wrong creating the goal. Please try again." }
      )
      expect(Goal.count).to eq(0)
      expect(Metric.count).to eq(0)
    end

    it "returns an inline error and creates nothing when no owner can be resolved" do
      allow(CreateUserFromSlack).to receive(:call).and_return(double(success?: false, user: nil))

      result = described_class.new(payload).call

      expect(result).to eq(
        response_action: "errors",
        errors: { "owners_block" => "A goal needs at least one owner. Please select one." }
      )
      expect(Goal.count).to eq(0)
    end

    it "still clears the modal (goal persisted) when posting the GoalDisplay fails" do
      sender = instance_double(Slack::Request::SendMessage)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      allow(sender).to receive(:send_message).and_raise(StandardError.new("slack down"))
      allow(Bugsnag).to receive(:notify)

      result = described_class.new(payload).call

      expect(result).to eq(response_action: "clear")
      expect(Goal.sole.metric).to be_present
      expect(Bugsnag).to have_received(:notify)
    end

    it "enqueues AgentResumeJob with a tool_result summarizing the created goal and org stats" do
      create(:goal, organization: organization, start_date: "2026-08-15", end_date: "2026-08-20")
      # This goal's own dates (factory default 2026-08-01..2026-09-01) also overlap the new
      # goal's period, so it counts toward goals_in_same_period too — 2 overlapping goals total.
      create(:initiative, goal: create(:goal, organization: organization))

      expect do
        described_class.new(payload).call
      end.to have_enqueued_job(AgentResumeJob).with(
        hash_including(
          agent_run_id: agent_run.id,
          slack_user_id: creator.provider_uid,
          tool_result: hash_including(
            status: "created",
            goal: hash_including(
              title: "Grow activation",
              publishing_status: "published",
              owners: [ owner.full_name ],
              metric: { name: "Activation rate", target_value: 40, unit: "%" },
            ),
            organization_stats: hash_including(
              goals_in_same_period: 2,
              unassigned_initiatives_on_goal: 0,
            ),
          ),
        )
      )
    end

    it "stamps produced_goal_id onto the run's pending_tool_call, preserving id/name/args" do
      described_class.new(payload).call

      expect(agent_run.reload.pending_tool_call).to include(
        "id" => "call_1", "name" => "show_goal_create_form", "produced_goal_id" => Goal.sole.id
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
          event: a_string_including("goal 'Grow activation' was created"),
        )
      )

      expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("AgentResumeJob")
    end
  end

  context "when the run already produced a goal (replayed submission)" do
    let(:produced_goal) do
      create(:goal, organization: organization, creator: creator, title: "Grow activation",
        start_date: "2026-08-01", end_date: "2026-09-01")
    end
    let!(:agent_run) do
      create(:agent_run, conversation: conversation, status: "paused_on_tool",
        pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form", "produced_goal_id" => produced_goal.id })
    end

    it "creates no duplicate goal, enqueues nothing, and updates the modal with the already-created info view" do
      expect do
        result = described_class.new(payload).call

        expect(result[:response_action]).to eq("update")
        expect(result[:view]).to be_a(Hash)
        text = result[:view][:blocks].sole[:text][:text]
        expect(text).to include("Grow activation")
        expect(text).to include(creator.full_name)
      end.not_to change(Goal, :count)

      expect(enqueued_jobs).to be_empty
    end

    it "falls back to generic copy when the produced goal has since been deleted" do
      agent_run # eager-load before destroying the goal it points at
      produced_goal.destroy!

      result = described_class.new(payload).call

      expect(result[:response_action]).to eq("update")
      expect(result[:view][:blocks].sole[:text][:text]).to eq("This goal was already created.")
    end
  end
end
