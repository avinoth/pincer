require "rails_helper"

RSpec.describe Slack::Views::CreateGoalModal do
  let(:conversation) { create(:conversation, slack_channel_id: "C1") }
  let(:agent_run) do
    create(:agent_run, conversation: conversation, status: "paused_on_tool",
      pending_tool_call: {
        "id" => "call_1", "name" => "show_goal_create_form",
        "args" => {
          "title" => "Grow activation",
          "metric_name" => "Activation rate", "metric_direction" => "increase",
          "metric_start_value" => 20, "metric_target_value" => 40, "metric_unit" => "%"
        }
      })
  end

  it "renders the single form — goal fields, inline metric, then admin fields — prefilled from the run's pending tool call args" do
    parent = create(:goal, organization: conversation.organization, title: "North Star")
    view = described_class.new(agent_run: agent_run, parent_goals: [ parent ]).to_h

    block_ids = view[:blocks].map { |b| b[:block_id] }
    expect(block_ids).to include(
      "title_block", "description_block", "owners_block", "start_date_block", "end_date_block",
      "name_block", "direction_block", "start_value_block", "target_value_block", "unit_block",
      "channel_block", "summary_day_block", "summary_time_block", "parent_block", "draft_block"
    )

    # Goal review fields, then metric, then admin tail (channel/summary/parent/draft).
    expect(block_ids.index("end_date_block")).to be < block_ids.index("name_block")
    expect(block_ids.index("unit_block")).to be < block_ids.index("channel_block")
    expect(block_ids.index("channel_block")).to be < block_ids.index("parent_block")
    expect(block_ids.index("parent_block")).to be < block_ids.index("draft_block")

    draft = view[:blocks].find { |b| b[:block_id] == "draft_block" }
    expect(draft[:optional]).to be(true)
    expect(draft[:element][:type]).to eq("checkboxes")
    expect(draft[:element]).not_to have_key(:initial_options)

    title = view[:blocks].find { |b| b[:block_id] == "title_block" }
    expect(title[:element][:initial_value]).to eq("Grow activation")
    expect(title[:optional]).to be(false)

    owners = view[:blocks].find { |b| b[:block_id] == "owners_block" }
    expect(owners[:element][:type]).to eq("multi_users_select")
    expect(owners[:optional]).to be(false)

    channel = view[:blocks].find { |b| b[:block_id] == "channel_block" }
    expect(channel[:element][:initial_conversation]).to eq("C1")

    summary_time = view[:blocks].find { |b| b[:block_id] == "summary_time_block" }
    expect(summary_time[:element][:initial_time]).to eq("17:00")
    expect(summary_time[:hint][:text]).to include("nudge")

    # Metric fields prefilled from the run's flat metric_* draft args.
    name = view[:blocks].find { |b| b[:block_id] == "name_block" }
    expect(name[:element][:initial_value]).to eq("Activation rate")
    target = view[:blocks].find { |b| b[:block_id] == "target_value_block" }
    expect(target[:element][:initial_value]).to eq("40")
    expect(target[:optional]).to be(false)

    expect(view[:callback_id]).to eq("create_goal")
    expect(view[:submit][:text]).to eq("Create goal")
    expect(JSON.parse(view[:private_metadata])).to eq("agent_run_id" => agent_run.id)
  end

  it "renders blank metric inputs when the run has no metric draft" do
    run = create(:agent_run, conversation: conversation, status: "paused_on_tool",
      pending_tool_call: { "id" => "call_1", "name" => "show_goal_create_form", "args" => { "title" => "Grow activation" } })
    view = described_class.new(agent_run: run).to_h

    name = view[:blocks].find { |b| b[:block_id] == "name_block" }
    expect(name[:element]).not_to have_key(:initial_value)
  end

  it "omits the parent field when there are no candidate goals" do
    view = described_class.new(agent_run: agent_run, parent_goals: []).to_h
    expect(view[:blocks].map { |b| b[:block_id] }).not_to include("parent_block")
  end
end
