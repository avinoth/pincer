require "rails_helper"

RSpec.describe Slack::Interactions::EditGoalSubmission do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }

  def payload(goal, values_overrides = {}, user_id: goal.creator.provider_uid, metadata: { "goal_id" => goal.id })
    values = {
      "title_block" => { "title" => { "value" => "Grow activation v2" } },
      "description_block" => { "description" => { "value" => "desc" } },
      "owners_block" => { "owners" => { "selected_users" => [ owner.provider_uid ] } },
      "start_date_block" => { "start_date" => { "selected_date" => "2026-08-01" } },
      "end_date_block" => { "end_date" => { "selected_date" => "2026-09-01" } },
      "channel_block" => { "channel" => { "selected_conversation" => "C_PICKED" } },
      "summary_day_block" => { "summary_day" => { "selected_option" => { "value" => "5" } } },
      "summary_time_block" => { "summary_time" => { "selected_time" => "17:00" } }
    }.deep_merge(values_overrides)

    {
      "type" => "view_submission",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "view" => {
        "callback_id" => "edit_goal",
        "private_metadata" => metadata.to_json,
        "state" => { "values" => values }
      }
    }
  end

  def draft_values(checked:)
    { "draft_block" => { "draft" => { "selected_options" => (checked ? [ { "value" => "draft" } ] : []) } } }
  end

  it "updates fields and stays a draft when the goal is a draft and the checkbox is checked" do
    goal = create(:goal, organization: organization, publishing_status: "draft", title: "Old title")

    result = described_class.new(payload(goal, draft_values(checked: true))).call

    expect(result).to eq(response_action: "clear")
    goal.reload
    expect(goal.title).to eq("Grow activation v2")
    expect(goal.owners).to contain_exactly(owner)
    expect(goal).to be_publishing_draft
  end

  it "publishes a draft goal when the checkbox is unchecked" do
    goal = create(:goal, organization: organization, publishing_status: "draft")

    result = described_class.new(payload(goal, draft_values(checked: false))).call

    expect(result).to eq(response_action: "clear")
    expect(goal.reload).to be_publishing_published
  end

  it "updates fields only for an already-published goal (no checkbox shown)" do
    goal = create(:goal, organization: organization, publishing_status: "published")

    result = described_class.new(payload(goal)).call

    expect(result).to eq(response_action: "clear")
    goal.reload
    expect(goal.title).to eq("Grow activation v2")
    expect(goal).to be_publishing_published
  end

  it "returns an inline error and makes no changes when no owner is selected" do
    goal = create(:goal, organization: organization, title: "Untouched")

    result = described_class.new(
      payload(goal, { "owners_block" => { "owners" => { "selected_users" => [] } } })
    ).call

    expect(result).to eq(response_action: "errors", errors: { "owners_block" => "Pick at least one owner" })
    expect(goal.reload.title).to eq("Untouched")
  end

  it "returns an inline error and makes no changes for an unauthorized submitter" do
    goal = create(:goal, organization: organization, title: "Untouched")

    result = described_class.new(payload(goal, user_id: "U_UNRELATED")).call

    expect(result).to eq(response_action: "errors", errors: { "title_block" => "You can't edit this goal." })
    expect(goal.reload.title).to eq("Untouched")
  end

  it "returns an inline error and makes no changes when the end date is before the start date" do
    goal = create(:goal, organization: organization, title: "Untouched")

    result = described_class.new(
      payload(goal, {
        "start_date_block" => { "start_date" => { "selected_date" => "2026-09-01" } },
        "end_date_block" => { "end_date" => { "selected_date" => "2026-08-01" } }
      })
    ).call

    expect(result).to eq(
      response_action: "errors", errors: { "end_date_block" => "End date can't be before the start date" }
    )
    expect(goal.reload.title).to eq("Untouched")
  end

  it "resolves the goal from JSON metadata's goal_id" do
    goal = create(:goal, organization: organization, title: "Untouched")

    result = described_class.new(payload(goal, metadata: { "goal_id" => goal.id })).call

    expect(result).to eq(response_action: "clear")
    expect(goal.reload.title).to eq("Grow activation v2")
  end

  describe "refreshing the goal's display after a successful update" do
    it "updates the origin card in place when message_ts is present" do
      goal = create(:goal, organization: organization, title: "Untouched")

      updater = instance_double(Slack::Request::UpdateMessage)
      allow(Slack::Request::UpdateMessage).to receive(:new).with(workspace).and_return(updater)
      expect(updater).to receive(:update_message) do |channel, ts, message|
        expect(channel).to eq("C_CARD")
        expect(ts).to eq("111.222")
        expect(message[:attachments].first[:blocks].to_s).to include("Grow activation v2")
      end
      allow(Slack::Request::SendMessage).to receive(:new)

      described_class.new(
        payload(goal, metadata: { "goal_id" => goal.id, "channel" => "C_CARD", "message_ts" => "111.222" })
      ).call

      expect(Slack::Request::SendMessage).not_to have_received(:new)
    end

    it "posts a fresh GoalDisplay in the thread when only channel (+ thread_ts) is present" do
      goal = create(:goal, organization: organization, title: "Untouched")

      sender = instance_double(Slack::Request::SendMessage)
      allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
      expect(sender).to receive(:send_message) do |channel, message|
        expect(channel).to eq("C_THREAD")
        expect(message[:thread_ts]).to eq("9.9")
        expect(message[:attachments].first[:blocks].to_s).to include("Grow activation v2")
      end
      allow(Slack::Request::UpdateMessage).to receive(:new)

      described_class.new(
        payload(goal, metadata: { "goal_id" => goal.id, "channel" => "C_THREAD", "thread_ts" => "9.9" })
      ).call

      expect(Slack::Request::UpdateMessage).not_to have_received(:new)
    end

    it "sends no message when neither message_ts nor channel is present" do
      goal = create(:goal, organization: organization, title: "Untouched")

      allow(Slack::Request::UpdateMessage).to receive(:new)
      allow(Slack::Request::SendMessage).to receive(:new)

      result = described_class.new(payload(goal, metadata: { "goal_id" => goal.id })).call

      expect(result).to eq(response_action: "clear")
      expect(Slack::Request::UpdateMessage).not_to have_received(:new)
      expect(Slack::Request::SendMessage).not_to have_received(:new)
    end
  end

  describe "the inline metric section" do
    def metric_values(overrides = {})
      {
        "name_block" => { "name" => { "value" => "Activation rate" } },
        "direction_block" => { "direction" => { "selected_option" => { "value" => "increase" } } },
        "start_value_block" => { "start_value" => { "value" => "20" } },
        "target_value_block" => { "target_value" => { "value" => "40" } },
        "unit_block" => { "unit" => { "value" => "%" } }
      }.deep_merge(overrides)
    end

    it "updates the metric when it's still editable (no MetricUpdate exists)" do
      goal = create(:goal, organization: organization)
      metric = create(:metric, goal: goal, name: "Old name", start_value: 0, target_value: 10)
      allow(Slack::Request::SendMessage).to receive(:new)

      result = described_class.new(payload(goal, metric_values)).call

      expect(result).to eq(response_action: "clear")
      metric.reload
      expect(metric.name).to eq("Activation rate")
      expect(metric.target_value).to eq(40)
      expect(metric.current_value).to eq(20)
    end

    it "returns an inline metric error and leaves both goal and metric unchanged when the metric fields are invalid" do
      goal = create(:goal, organization: organization, title: "Untouched")
      metric = create(:metric, goal: goal, name: "Old name")

      result = described_class.new(
        payload(goal, metric_values("target_value_block" => { "target_value" => { "value" => "" } }))
      ).call

      expect(result).to eq(response_action: "errors", errors: { "target_value_block" => "Please set a target value" })
      # The metric fields are validated up front, before UpdateGoal runs, so an
      # invalid metric never leaves the goal-field changes half-applied.
      expect(goal.reload.title).to eq("Untouched")
      expect(metric.reload.name).to eq("Old name")
    end

    it "leaves the metric untouched once a MetricUpdate exists, even if edited fields are submitted" do
      goal = create(:goal, organization: organization)
      metric = create(:metric, goal: goal, name: "Locked name")
      create(:metric_update, metric: metric)
      allow(Slack::Request::SendMessage).to receive(:new)

      result = described_class.new(payload(goal, metric_values)).call

      expect(result).to eq(response_action: "clear")
      expect(metric.reload.name).to eq("Locked name")
    end
  end
end
