# frozen_string_literal: true

# Handles submission of the single Create Goal modal (goal fields plus the
# mandatory primary metric, inline — see Slack::Views::CreateGoalModal): all
# fields validate in one pass, and on success the Goal and its Metric are
# created together, atomically (CreateGoal.call! + CreateMetric.call! — either
# bang raises Interactor::Failure on failure, rolling both back). On success,
# posts the GoalDisplay card (draft or published — it's already state-aware),
# clears the modal, and resumes (or narrates back into) the originating
# AgentRun.
#
# private_metadata is JSON {"agent_run_id" => id}, set by
# Slack::Interactions::AgentOpenCreateGoalModal (see Slack::Views::CreateGoalModal).
class Slack::Interactions::CreateGoalSubmission < Slack::Interactions::Base
  include Slack::Interactions::GoalForm
  include Slack::Interactions::MetricForm

  def call
    return unless organization

    # A replayed submission must not create a second goal. #trigger_agent_hook
    # stamps produced_goal_id onto the run's pending_tool_call once the goal
    # exists, so its presence means this submission already completed for this
    # run — swap in the read-only GoalAlreadyCreatedModal rather than minting a
    # duplicate Goal + Metric (and a duplicate GoalDisplay card, or a second
    # AgentResumeJob/AgentTurnJob enqueue). This is the only branch that can
    # observe a genuine race — user B's modal legitimately open before user A's
    # submission landed — so B gets told what happened instead of a silent
    # close. Slack's own HTTP-retry replays of this same request never render
    # the response, so returning "update" here doesn't reopen anything for those.
    return { response_action: "update", view: already_created_view.to_h } if agent_run_already_produced?

    errors = combined_errors
    return { response_action: "errors", errors: errors } if errors.present?

    owners = Array(owner_slack_ids).filter_map do |uid|
      result = CreateUserFromSlack.call(organization: organization, slack_user_id: uid)
      result.user if result.success?
    end
    return error("owners_block", "A goal needs at least one owner. Please select one.") if owners.empty?

    creator = CreateUserFromSlack.call(organization: organization, slack_user_id: user_id).user
    return error("title_block", "Couldn't identify who's creating this goal. Please try again.") if creator.nil?

    goal = create_goal_and_metric(creator, owners)
    post_goal_display(goal)
    trigger_agent_hook(goal)
    { response_action: "clear" }
  rescue Interactor::Failure
    error("title_block", "Something went wrong creating the goal. Please try again.")
  end

  private

  # All blocking validation failures across both the goal fields and the
  # metric fields, gathered in one pass and keyed by block_id — shown to the
  # user together, rather than forcing a fix-one-submit-again loop.
  def combined_errors
    errors = {}
    errors["title_block"] = "Please enter a goal title" if title.blank?
    errors["owners_block"] = "Pick at least one owner" if owner_slack_ids.empty?
    errors["start_date_block"] = "Please pick a start date" if start_date.blank?

    if end_date.blank?
      errors["end_date_block"] = "Please pick an end date"
    elsif end_before_start?
      errors["end_date_block"] = "End date can't be before the start date"
    end

    errors["name_block"] = "Please name what to track" if metric_name.blank?
    errors["direction_block"] = "Pick increase or decrease" if metric_direction.blank?
    errors["target_value_block"] = "Please set a target value" if metric_target_value.blank?

    errors
  end

  def create_goal_and_metric(creator, owners)
    goal = nil

    ActiveRecord::Base.transaction do
      goal = CreateGoal.call!(
        organization: organization,
        creator: creator,
        owners: owners,
        title: title,
        description: description,
        start_date: start_date,
        end_date: end_date,
        update_channel: channel.presence || agent_run&.conversation&.slack_channel_id,
        summary_day: summary_day,
        summary_time: summary_time,
        parent: parent_goal,
        draft: draft_checked?,
      ).goal

      CreateMetric.call!(
        goal: goal,
        name: metric_name,
        direction: metric_direction,
        start_value: metric_start_value,
        target_value: metric_target_value,
        unit: metric_unit,
      )
    end

    goal
  end

  def metadata
    @metadata ||= JSON.parse(payload.dig(:view, :private_metadata).to_s)
  rescue JSON::ParserError
    nil
  end

  def agent_run_id
    metadata.is_a?(Hash) ? metadata["agent_run_id"] : nil
  end

  def agent_run
    return nil unless agent_run_id

    @agent_run ||= AgentRun.find_by(id: agent_run_id)
  end

  def agent_run_already_produced?
    agent_run&.pending_tool_call&.dig("produced_goal_id").present?
  end

  # Org-scoped so a stale/foreign goal id never leaks another org's goal title.
  def already_created_view
    goal_id = agent_run.pending_tool_call["produced_goal_id"]
    Slack::Views::GoalAlreadyCreatedModal.new(goal: organization.goals.find_by(id: goal_id))
  end

  # Best-effort: the Goal + Metric are already committed by the time we post, so
  # a failed Slack request must not raise out of #call — that would deny Slack
  # the clear response and leave the (successfully persisted) submission open for
  # a retry. Report it and move on; the idempotency guard covers any retry.
  def post_goal_display(goal)
    return if display_channel_id.blank?

    Slack::Request::SendMessage.new(organization.slack_workspace).send_message(
      display_channel_id,
      Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: display_thread_ts),
    )
  rescue => e
    Bugsnag.notify(e, { goal_id: goal.id })
  end

  def display_channel_id
    agent_run&.conversation&.slack_channel_id
  end

  def display_thread_ts
    agent_run&.conversation&.slack_thread_ts
  end

  # Resumes the paused run inline-fast (enqueues — Resume is a full LLM round
  # trip, too slow for Slack's 3s window) when it's still waiting on exactly
  # this form; otherwise the run has moved on since the form was shown
  # (resolve-once rule, case ii — settled decision #5), so we narrate the
  # outcome back in as a fresh turn instead of resuming a run that no longer
  # expects this tool result. Either way, stamp produced_goal_id onto the run
  # first: a replayed submission is caught by #agent_run_already_produced? at
  # the top of #call, before a second Goal (or a second enqueue) is ever created.
  def trigger_agent_hook(goal)
    run = agent_run
    return if run.nil?

    mark_produced(run, goal)

    if run.status_paused_on_tool? && run.pending_tool_call&.dig("name") == "show_goal_create_form"
      AgentResumeJob.perform_later(agent_run_id: run.id, slack_user_id: user_id, tool_result: tool_result_for(goal))
    else
      enqueue_late_submit_event(run, goal)
    end
  end

  # Merge-don't-overwrite, same discipline as Ai::Agent::Tools::ShowGoalCreateForm
  # #persist_draft and Ai::Agent::Runner#record_pending_tool_call — pending_tool_call
  # already carries "id"/"name"/"args" and those must survive this update.
  def mark_produced(run, goal)
    pending = (run.pending_tool_call || {}).stringify_keys
    pending["produced_goal_id"] = goal.id
    run.update!(pending_tool_call: pending)
  end

  def tool_result_for(goal)
    metric = goal.metric

    {
      status: "created",
      goal: {
        id: goal.id,
        title: goal.title,
        start_date: goal.start_date,
        end_date: goal.end_date,
        publishing_status: goal.publishing_status,
        owners: goal.owners.map(&:full_name),
        metric: metric && { name: metric.name, target_value: metric.target_value, unit: metric.unit }
      },
      organization_stats: {
        goals_in_same_period: goals_in_same_period(goal),
        days_until_start: (goal.start_date - Date.current).to_i,
        unassigned_initiatives_on_goal: goal.initiatives.where(owner_id: nil).count
      }
    }
  end

  # Overlap semantics mirror Ai::Agent::Tools::ListGoals#filter_by_period: a
  # goal is in-period if it hasn't ended before the new goal starts, and hasn't
  # started after the new goal ends.
  def goals_in_same_period(goal)
    organization.goals.where.not(id: goal.id)
      .where("end_date >= ?", goal.start_date)
      .where("start_date <= ?", goal.end_date)
      .count
  end

  def enqueue_late_submit_event(run, goal)
    conversation = run.conversation

    AgentTurnJob.perform_later(
      slack_team_id: organization.slack_workspace.identifier,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      surface: conversation.surface,
      slack_user_id: user_id,
      event: "user has now submitted the previously displayed goal form; " \
             "goal '#{goal.title}' was created (id #{goal.id}).",
    )
  end
end
