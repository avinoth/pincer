# frozen_string_literal: true

# Handles submission of the Edit Goal modal: parses the modal state (fields
# shared with CreateGoalSubmission via GoalForm), resolves owners, and
# delegates the update to UpdateGoal. A single step — no wizard push, no
# in-modal block-action. Publishing is derived from the goal's current
# publishing status plus the (possibly absent) Draft checkbox:
#   - draft goal, checkbox unchecked  → publish
#   - draft goal, checkbox checked    → stays draft
#   - already-published goal          → checkbox isn't shown; never re-drafts
#
# On success, refreshes the goal's display in Slack from the modal's
# private_metadata (see Slack::Views::EditGoalModal): edited from a card →
# update that card in place; edited from a command (thread context, no card)
# → post a fresh GoalDisplay in the thread; neither → nothing to refresh.
#
# The metric is handled after the goal update succeeds: if it's still editable
# (no MetricUpdate exists yet) its fields are validated and applied via
# UpdateMetric; if it's frozen, it's ignored entirely — the modal never rendered
# inputs for it, so there's nothing in the submitted state to apply. Goal-field
# edits are allowed either way.
class Slack::Interactions::EditGoalSubmission < Slack::Interactions::Base
  include Slack::Interactions::GoalForm
  include Slack::Interactions::MetricForm

  def call
    return error("title_block", "Please enter a goal title") if title.blank?
    return error("owners_block", "Pick at least one owner") if owner_slack_ids.empty?
    return error("start_date_block", "Please pick a start date") if start_date.blank?
    return error("end_date_block", "Please pick an end date") if end_date.blank?
    return error("end_date_block", "End date can't be before the start date") if end_before_start?
    return unless organization
    return if goal.nil?
    return error("title_block", "You can't edit this goal.") unless goal.modifiable_by?(user_id)

    # Validate the metric fields up front (only when editable) so a metric error
    # never leaves the goal-field changes half-applied — UpdateGoal below only
    # runs once we know the whole submission is valid.
    if metric_editable?
      metric_error = metric_errors
      return metric_error if metric_error
    end

    # Provision any selected owners that aren't in our DB yet (find-or-create).
    owners = owner_slack_ids.filter_map do |uid|
      result = CreateUserFromSlack.call(organization: organization, slack_user_id: uid)
      result.user if result.success?
    end
    return error("owners_block", "A goal needs at least one owner. Please select one.") if owners.empty?

    result = UpdateGoal.call(
      goal: goal,
      attributes: {
        title: title,
        description: description,
        start_date: start_date,
        end_date: end_date,
        update_channel: channel.presence || goal.update_channel,
        summary_day: summary_day,
        summary_time: summary_time,
        parent: parent_goal,
        owners: owners
      },
      publish: goal.publishing_draft? ? !draft_checked? : false,
    )
    return error("title_block", "Something went wrong updating the goal. Please try again.") unless result.success?

    if metric_editable?
      return error("name_block", "Something went wrong updating the metric. Please try again.") unless update_metric.success?
    end

    refresh_display(result.goal)
    { response_action: "clear" }
  end

  private

  # Once any MetricUpdate exists the metric is frozen (see
  # Slack::Views::EditGoalModal) — no inputs were rendered for it, so it's left
  # untouched. Nil-guarded defensively; in practice every goal has a metric.
  def metric_editable?
    return @metric_editable if defined?(@metric_editable)

    @metric_editable = goal.metric.present? && !goal.metric.metric_updates.exists?
  end

  def update_metric
    UpdateMetric.call(
      metric: goal.metric,
      name: metric_name,
      direction: metric_direction,
      start_value: metric_start_value,
      target_value: metric_target_value,
      unit: metric_unit,
    )
  end

  def goal
    @goal ||= organization.goals.find_by(id: metadata["goal_id"])
  end

  # private_metadata is JSON — { goal_id, channel?, message_ts?, thread_ts? }
  # — set by Slack::Views::EditGoalModal.
  def metadata
    @metadata ||= JSON.parse(payload.dig(:view, :private_metadata))
  end

  def refresh_display(goal)
    card = Slack::Messages::GoalDisplay.new(goal: goal).to_h

    if metadata["message_ts"].present?
      Slack::Request::UpdateMessage.new(organization.slack_workspace)
        .update_message(metadata["channel"], metadata["message_ts"], card)
    elsif metadata["channel"].present?
      Slack::Request::SendMessage.new(organization.slack_workspace)
        .send_message(metadata["channel"], card.merge(thread_ts: metadata["thread_ts"]))
    end
  end
end
