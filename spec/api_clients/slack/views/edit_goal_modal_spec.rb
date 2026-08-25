require "rails_helper"

RSpec.describe Slack::Views::EditGoalModal do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) do
    create(:goal, organization: organization, title: "Grow activation", description: "desc",
      update_channel: "C1", summary_day: 2, summary_time: "17:00", owners: [ owner ])
  end

  it "prefills the form from the goal" do
    view = described_class.new(goal: goal).to_h

    block_ids = view[:blocks].map { |b| b[:block_id] }
    expect(block_ids).to include(
      "title_block", "description_block", "owners_block", "start_date_block",
      "end_date_block", "channel_block", "summary_day_block", "summary_time_block"
    )

    title = view[:blocks].find { |b| b[:block_id] == "title_block" }
    expect(title[:element][:initial_value]).to eq("Grow activation")

    owners = view[:blocks].find { |b| b[:block_id] == "owners_block" }
    expect(owners[:element][:initial_users]).to eq([ "U_OWNER" ])

    channel = view[:blocks].find { |b| b[:block_id] == "channel_block" }
    expect(channel[:element][:initial_conversation]).to eq("C1")

    start_date = view[:blocks].find { |b| b[:block_id] == "start_date_block" }
    expect(start_date[:element][:initial_date]).to eq(goal.start_date.iso8601)

    expect(view[:callback_id]).to eq("edit_goal")
    expect(JSON.parse(view[:private_metadata])).to eq("goal_id" => goal.id)
    expect(view[:submit][:text]).to eq("Update goal")
  end

  it "folds the origin card's coordinates into private_metadata when given" do
    view = described_class.new(
      goal: goal, origin: { channel: "C1", message_ts: "111.222" }
    ).to_h

    expect(JSON.parse(view[:private_metadata])).to eq(
      "goal_id" => goal.id, "channel" => "C1", "message_ts" => "111.222"
    )
  end

  it "omits origin keys entirely when no origin is given" do
    view = described_class.new(goal: goal).to_h

    expect(JSON.parse(view[:private_metadata]).keys).to eq([ "goal_id" ])
  end

  it "shows the Draft checkbox, checked, for a draft goal" do
    draft_goal = create(:goal, organization: organization, publishing_status: "draft")

    view = described_class.new(goal: draft_goal).to_h

    draft = view[:blocks].find { |b| b[:block_id] == "draft_block" }
    expect(draft).to be_present
    expect(draft[:element][:initial_options]).to be_present
  end

  it "omits the Draft checkbox for a published goal" do
    view = described_class.new(goal: goal).to_h

    expect(view[:blocks].map { |b| b[:block_id] }).not_to include("draft_block")
  end

  it "includes a parent field with the goal's current parent preselected" do
    parent = create(:goal, organization: organization, title: "North Star")
    goal.update!(parent: parent)

    view = described_class.new(goal: goal, parent_goals: [ parent ]).to_h

    parent_block = view[:blocks].find { |b| b[:block_id] == "parent_block" }
    expect(parent_block[:element][:initial_option][:value]).to eq(parent.id.to_s)
  end

  it "omits the metric section entirely when the goal has no metric" do
    view = described_class.new(goal: goal).to_h

    expect(view[:blocks].map { |b| b[:block_id] }).not_to include("name_block")
  end

  describe "the metric section" do
    it "renders editable metric inputs, prefilled, when no MetricUpdate exists yet" do
      metric = create(:metric, goal: goal, name: "Activation rate", direction: "increase",
        start_value: 20, target_value: 40, unit: "%")

      view = described_class.new(goal: goal).to_h

      expect(view[:blocks].to_s).to include("*Metric*")
      name_input = view[:blocks].find { |b| b[:block_id] == "name_block" }[:element]
      expect(name_input[:initial_value]).to eq(metric.name)
      target_input = view[:blocks].find { |b| b[:block_id] == "target_value_block" }[:element]
      expect(target_input[:initial_value]).to eq("40")
    end

    it "renders the metric as frozen, read-only text once a MetricUpdate exists" do
      metric = create(:metric, goal: goal)
      create(:metric_update, metric: metric)

      view = described_class.new(goal: goal).to_h

      expect(view[:blocks].map { |b| b[:block_id] }).not_to include("name_block", "target_value_block")
      expect(view[:blocks].to_s).to include(metric.name)
      expect(view[:blocks].to_s).to include("Locked")
    end
  end
end
