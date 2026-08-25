# frozen_string_literal: true

# Edit an existing Goal. Same field layout/action_ids as CreateGoalModal so
# EditGoalSubmission can share Slack::Interactions::GoalForm with
# CreateGoalSubmission — prefilled from the goal instead of an extracted
# draft. private_metadata is a JSON blob — { goal_id, channel?, message_ts?,
# thread_ts? } — carrying both the goal id and the origin card's coordinates
# (when opened from one), so EditGoalSubmission can refresh the right message
# on submit. See Slack::Interactions::OpenEditGoalModal / EditGoalSubmission.
#
# The "Draft" checkbox is shown (checked) only for a goal that's still a
# draft; a published goal can never move back to draft, so the checkbox is
# simply omitted rather than surfacing an error.
#
# The metric is rendered inline below the goal fields: editable input blocks
# while it has no MetricUpdate yet, or frozen read-only text once one exists
# (Slack can't grey out an input block). See Slack::Views::MetricFields.
class Slack::Views::EditGoalModal < Slack::Views::Modal
  include Slack::Views::MetricFields

  CALLBACK_ID = "edit_goal"

  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  # @param parent_goals [Enumerable<Goal>] candidate parent goals (org's in-progress goals)
  # @param origin [Hash, nil] the opening context's coordinates — { channel:, message_ts:, thread_ts: }.
  def initialize(goal:, parent_goals: [], origin: nil)
    @goal = goal
    @parent_goals = parent_goals.to_a
    @origin = origin
  end

  def callback_id
    CALLBACK_ID
  end

  def title
    "Edit Goal"
  end

  def submit_label
    "Update goal"
  end

  def private_metadata
    {
      goal_id: @goal.id,
      channel: @origin&.dig(:channel),
      message_ts: @origin&.dig(:message_ts),
      thread_ts: @origin&.dig(:thread_ts)
    }.compact.to_json
  end

  def blocks
    [
      input(
        label: "Title",
        block_id: "title_block",
        element: plain_text_input(action_id: "title", initial_value: @goal.title, max_length: 255),
      ),
      input(
        label: "Description",
        block_id: "description_block",
        optional: true,
        element: plain_text_input(
          action_id: "description",
          multiline: true,
          initial_value: @goal.description.presence,
          max_length: 2000,
        ),
      ),
      input(
        label: "Owner(s)",
        block_id: "owners_block",
        element: multi_users_select(
          action_id: "owners",
          placeholder: "Select one or more owners",
          initial_users: @goal.owners.map(&:provider_uid),
        ),
      ),
      input(
        label: "Start date",
        block_id: "start_date_block",
        element: datepicker(
          action_id: "start_date",
          placeholder: "Select Goal's start date",
          initial_date: @goal.start_date&.iso8601,
        ),
      ),
      input(
        label: "End date",
        block_id: "end_date_block",
        element: datepicker(
          action_id: "end_date",
          placeholder: "Select Goal's end date",
          initial_date: @goal.end_date&.iso8601,
        ),
      ),
      input(
        label: "Notification channel",
        block_id: "channel_block",
        optional: true,
        element: conversations_select(
          action_id: "channel",
          placeholder: "Select a channel",
          initial_conversation: @goal.update_channel,
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
          initial_option: @goal.summary_day && day_option(@goal.summary_day),
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
          initial_time: @goal.summary_time,
        ),
      ),
      *parent_block,
      *draft_block,
      *metric_blocks
    ]
  end

  private

  # Nil-guarded defensively — in practice every goal has a metric, but a handful
  # of specs/seeds build goals without one.
  def metric_blocks
    metric = @goal.metric
    return [] if metric.nil?

    [
      divider,
      section("*Metric*"),
      *(metric.metric_updates.exists? ? metric_readonly_blocks(metric) : metric_input_blocks(metric))
    ]
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
          initial_option: @goal.parent && option(@goal.parent.title, @goal.parent.id.to_s),
        ),
      )
    ]
  end

  def draft_block
    return [] unless @goal.publishing_draft?

    checked = option("Save as draft", "draft")

    [
      input(
        label: "Draft",
        block_id: "draft_block",
        optional: true,
        element: checkboxes(action_id: "draft", options: [ checked ], initial_options: [ checked ]),
      )
    ]
  end
end
