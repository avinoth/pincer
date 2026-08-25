require "rails_helper"

RSpec.describe Ai::Agent::Tools::ShowGoals do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "posts a GoalSummaryList threaded in the conversation" do
    goal_a = create(:goal, organization: organization, title: "Grow activation")
    goal_b = create(:goal, organization: organization, title: "Cut churn")

    tool.execute

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:attachments].size).to eq(2)
      expect(payload[:attachments].to_s).to include(goal_a.title).and include(goal_b.title)
    end
  end

  it "returns posted: true, shown/total counts, and a compact summary of the shown goals" do
    owner = create(:user, organization: organization, full_name: "Ada Lovelace")
    goal = create(:goal, organization: organization, title: "Grow activation", owners: [ owner ])
    create(:metric, goal: goal, name: "MRR", current_value: 20, target_value: 40, unit: "%")

    result = tool.execute

    expect(result[:posted]).to eq(true)
    expect(result[:shown]).to eq(1)
    expect(result[:total]).to eq(1)
    expect(result[:goals]).to eq([
      {
        id: goal.id, title: "Grow activation", start_date: goal.start_date, end_date: goal.end_date,
        status: goal.status, publishing_status: goal.publishing_status, health: goal.health,
        owners: [ "Ada Lovelace" ], metric: { name: "MRR", current: BigDecimal("20"), target: BigDecimal("40"), unit: "%" }
      }
    ])
  end

  it "caps shown goals at MAX_SUMMARY_CARDS while total reflects the full matching count" do
    create_list(:goal, Slack::Messages::GoalSummaryList::MAX_SUMMARY_CARDS + 3, organization: organization)

    result = tool.execute

    expect(result[:shown]).to eq(Slack::Messages::GoalSummaryList::MAX_SUMMARY_CARDS)
    expect(result[:total]).to eq(Slack::Messages::GoalSummaryList::MAX_SUMMARY_CARDS + 3)
    expect(result[:goals].size).to eq(Slack::Messages::GoalSummaryList::MAX_SUMMARY_CARDS)
  end

  it "sorts active goals (in_progress, not_started) before completed/ended, then by soonest end_date" do
    ended = create(:goal, organization: organization, title: "Ended", status: "ended", end_date: 1.day.from_now.to_date)
    in_progress_far = create(:goal, organization: organization, title: "In progress far", status: "in_progress",
      end_date: 30.days.from_now.to_date)
    in_progress_near = create(:goal, organization: organization, title: "In progress near", status: "in_progress",
      end_date: 5.days.from_now.to_date)
    not_started = create(:goal, organization: organization, title: "Not started", status: "not_started",
      end_date: 10.days.from_now.to_date)

    result = tool.execute

    expect(result[:goals].map { |g| g[:id] }).to eq(
      [ in_progress_near.id, in_progress_far.id, not_started.id, ended.id ]
    )
  end

  describe "filtering" do
    it "filters by period overlap, status, publishing_status, and owner, same as list_goals" do
      owner = create(:user, organization: organization, provider_uid: "U_OWNER")
      matching = create(:goal, organization: organization, status: "not_started", publishing_status: "draft",
        owners: [ owner ], start_date: "2026-07-10", end_date: "2026-07-20")
      create(:goal, organization: organization, status: "in_progress", publishing_status: "published")

      result = tool.execute(start_date: "2026-07-01", end_date: "2026-07-31", status: "not_started",
        publishing_status: "draft", owner: "U_OWNER")

      expect(result[:goals].map { |g| g[:id] }).to eq([ matching.id ])
    end

    it "scopes to the given organization only" do
      create(:goal)
      own_goal = create(:goal, organization: organization)

      result = tool.execute

      expect(result[:goals].map { |g| g[:id] }).to eq([ own_goal.id ])
    end
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute

    expect(result).to eq(error: "Couldn't show goals: boom")
    expect(send_message).not_to have_received(:send_message)
  end
end
