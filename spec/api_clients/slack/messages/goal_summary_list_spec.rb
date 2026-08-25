require "rails_helper"

RSpec.describe Slack::Messages::GoalSummaryList do
  let(:organization) { create(:organization) }

  def buttons(attachment)
    attachment[:blocks].flat_map { |b| Array(b[:elements]) }.select { |e| e[:type] == "button" }
  end

  it "emits one attachment per goal, each colored by GoalCardPresenter#card_color" do
    goal_a = create(:goal, organization: organization, title: "Grow activation", status: "in_progress", health: nil)
    goal_b = create(:goal, organization: organization, title: "Cut churn", status: "completed", health: nil)

    payload = described_class.new(goals: [ goal_a, goal_b ], total: 2).to_h

    expect(payload[:attachments].size).to eq(2)
    expect(payload[:attachments][0][:color]).to eq(Slack::GoalCardPresenter.new(goal: goal_a).card_color)
    expect(payload[:attachments][1][:color]).to eq(Slack::GoalCardPresenter.new(goal: goal_b).card_color)
  end

  it "includes a top-level header block stating the total count" do
    goal = create(:goal, organization: organization)

    payload = described_class.new(goals: [ goal ], total: 1).to_h

    expect(payload[:blocks].to_s).to include("1 goal")
  end

  it "puts a section (badge + title + progress bar), a context line, and a View details button on each card" do
    goal = create(:goal, organization: organization, title: "Grow activation", status: "in_progress",
      end_date: "2026-09-15")
    owner = create(:user, organization: organization, full_name: "Ada Lovelace")
    goal.owners = [ owner ]
    create(:metric, goal: goal, name: "MRR", direction: "increase", start_value: 0, current_value: 3, target_value: 10)

    payload = described_class.new(goals: [ goal ], total: 1).to_h
    attachment = payload[:attachments].first

    text = attachment[:blocks].to_s
    expect(text).to include("🟢 In progress")
    expect(text).to include("Grow activation")
    expect(text).to include("▓▓▓░░░░░░░ 30%")
    expect(text).to include("MRR: 3% → 10% ↗︎")
    expect(text).to include("Ada Lovelace")
    expect(text).to include("ends Sep 15")

    goal_buttons = buttons(attachment)
    expect(goal_buttons.size).to eq(1)
    expect(goal_buttons.first[:action_id]).to eq(described_class::VIEW_DETAIL_ACTION_ID)
    expect(goal_buttons.first[:value]).to eq(goal.id.to_s)
    expect(goal_buttons.first[:text][:text]).to eq("View details")
  end

  it "caps cards at MAX_SUMMARY_CARDS and appends an overflow context attachment" do
    goals = create_list(:goal, described_class::MAX_SUMMARY_CARDS + 3, organization: organization)

    payload = described_class.new(goals: goals, total: goals.size).to_h

    card_attachments = payload[:attachments][0...described_class::MAX_SUMMARY_CARDS]
    expect(card_attachments.size).to eq(described_class::MAX_SUMMARY_CARDS)

    overflow = payload[:attachments].last
    expect(overflow[:blocks].to_s).to include("…and 3 more — ask me to filter")
    expect(overflow).not_to have_key(:color)
  end

  it "adds no overflow attachment when total does not exceed what's shown" do
    goal = create(:goal, organization: organization)

    payload = described_class.new(goals: [ goal ], total: 1).to_h

    expect(payload[:attachments].size).to eq(1)
    expect(payload[:attachments].to_s).not_to include("more")
  end

  it "sets the plain-text summary to the total goal count" do
    goal = create(:goal, organization: organization)

    expect(described_class.new(goals: [ goal ], total: 1).to_h[:text]).to eq("1 goal")
    expect(described_class.new(goals: [ goal ], total: 5).to_h[:text]).to eq("5 goals")
  end
end
