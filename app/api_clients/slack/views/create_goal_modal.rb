# frozen_string_literal: true

# The Create Goal form — goal fields plus the mandatory primary metric, inline
# in a single modal. Prefilled from the extracted draft. Submitting validates
# everything in one pass and creates the Goal and its Metric together,
# atomically (see Slack::Interactions::CreateGoalSubmission) — closing the
# modal leaves zero rows behind.
#
# Offered by the agent flow (Ai::Agent::Tools::ShowGoalCreateForm /
# AgentOpenCreateGoalModal): pass `agent_run:` (the paused AgentRun). Draft
# comes from agent_run.pending_tool_call["args"] — goal fields directly, metric
# fields from the flat metric_* keys (see #metric_draft), remapped to the
# plain name/direction/start_value/target_value/unit keys
# Slack::Views::MetricFields expects. private_metadata is JSON
# {"agent_run_id" => id} that CreateGoalSubmission reads back.
class Slack::Views::CreateGoalModal < Slack::Views::Modal
  include Slack::Views::MetricFields

  CALLBACK_ID = "create_goal"

  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  DEFAULT_SUMMARY_DAY = 5 # Friday
  DEFAULT_SUMMARY_TIME = "17:00"

  # @param parent_goals [Enumerable<Goal>] candidate parent goals (org's in-progress goals)
  def initialize(agent_run:, parent_goals: [])
    @agent_run = agent_run
    @draft = (draft_source || {}).with_indifferent_access
    @parent_goals = parent_goals.to_a
  end

  def callback_id
    CALLBACK_ID
  end

  def title
    "Create Goal"
  end

  def submit_label
    "Create goal"
  end

  def private_metadata
    { agent_run_id: @agent_run.id }.to_json
  end

  def blocks
    [
      input(
        label: "Title",
        block_id: "title_block",
        element: plain_text_input(
          action_id: "title",
          initial_value: @draft[:title].presence,
          max_length: 255,
        ),
      ),
      input(
        label: "Description",
        block_id: "description_block",
        optional: true,
        element: plain_text_input(
          action_id: "description",
          multiline: true,
          initial_value: @draft[:description].presence,
          max_length: 2000,
        ),
      ),
      input(
        label: "Owner(s)",
        block_id: "owners_block",
        element: multi_users_select(action_id: "owners", placeholder: "Select one or more owners"),
      ),
      input(
        label: "Start date",
        block_id: "start_date_block",
        element: datepicker(
          action_id: "start_date",
          placeholder: "Select Goal's start date",
          initial_date: @draft[:start_date].presence,
        ),
      ),
      input(
        label: "End date",
        block_id: "end_date_block",
        element: datepicker(
          action_id: "end_date",
          placeholder: "Select Goal's end date",
          initial_date: @draft[:end_date].presence,
        ),
      ),
      divider,
      section("*Metric*"),
      *metric_input_blocks(metric_draft),
      input(
        label: "Notification channel",
        block_id: "channel_block",
        optional: true,
        element: conversations_select(
          action_id: "channel",
          placeholder: "Select a channel",
          initial_conversation: source_channel_id,
          include: %w[public private],
        ),
      ),
      input(
        label: "Summary day",
        block_id: "summary_day_block",
        optional: true,
        element: static_select(
          action_id: "summary_day",
          placeholder: "Select a day",
          options: day_options,
          initial_option: day_option(DEFAULT_SUMMARY_DAY),
        ),
      ),
      input(
        label: "Summary time",
        block_id: "summary_time_block",
        optional: true,
        hint: "A nudge to update metrics is sent a day before and 4 hours before the summary.",
        element: timepicker(
          action_id: "summary_time",
          placeholder: "Select a time",
          initial_time: DEFAULT_SUMMARY_TIME,
        ),
      ),
      *parent_block,
      draft_block
    ]
  end

  private

  def draft_source
    @agent_run.pending_tool_call&.dig("args")
  end

  def source_channel_id
    @agent_run.conversation.slack_channel_id
  end

  # The flat metric_* keys ShowGoalCreateForm persisted onto the run's
  # pending_tool_call args, remapped to the plain name/direction/start_value/
  # target_value/unit keys Slack::Views::MetricFields expects.
  def metric_draft
    {
      "name" => @draft[:metric_name],
      "direction" => @draft[:metric_direction],
      "start_value" => @draft[:metric_start_value],
      "target_value" => @draft[:metric_target_value],
      "unit" => @draft[:metric_unit]
    }.compact
  end

  def draft_block
    input(
      label: "Draft",
      block_id: "draft_block",
      optional: true,
      element: checkboxes(
        action_id: "draft",
        options: [ option("Save as draft", "draft") ],
      ),
    )
  end

  def day_options
    DAY_NAMES.each_index.map { |i| day_option(i) }
  end

  def day_option(index)
    option(DAY_NAMES[index], index.to_s)
  end

  def parent_block
    return [] if @parent_goals.empty?

    [
      input(
        label: "Parent goal",
        block_id: "parent_block",
        optional: true,
        element: static_select(
          action_id: "parent",
          placeholder: "Select a parent goal",
          options: @parent_goals.map { |g| option(g.title, g.id.to_s) },
        ),
      )
    ]
  end
end
