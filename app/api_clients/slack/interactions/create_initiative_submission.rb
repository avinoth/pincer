# frozen_string_literal: true

# Handles submission of the Create Initiative modal (see
# Slack::Views::CreateInitiativeModal): validates goal/title/owner in one
# pass, provisions the owner and the submitting user as creator (find-or-create
# from Slack), and creates the Initiative via CreateInitiative. On success,
# posts the InitiativeDisplay card, clears the modal, and resumes (or narrates
# back into) the originating AgentRun.
#
# private_metadata is JSON {"agent_run_id" => id}, set by
# Slack::Interactions::AgentOpenCreateInitiativeModal (see
# Slack::Views::CreateInitiativeModal).
class Slack::Interactions::CreateInitiativeSubmission < Slack::Interactions::Base
  include Slack::Interactions::InitiativeForm

  def call
    return unless organization

    # A replayed submission must not create a second initiative.
    # #trigger_agent_hook stamps produced_initiative_id onto the run's
    # pending_tool_call once the initiative exists, so its presence means this
    # submission already completed for this run — swap in the read-only
    # InitiativeAlreadyCreatedModal rather than minting a duplicate Initiative
    # (and a duplicate InitiativeDisplay card, or a second
    # AgentResumeJob/AgentTurnJob enqueue). This is the only branch that can
    # observe a genuine race — user B's modal legitimately open before user
    # A's submission landed — so B gets told what happened instead of a silent
    # close. Slack's own HTTP-retry replays of this same request never render
    # the response, so returning "update" here doesn't reopen anything for
    # those.
    return { response_action: "update", view: already_created_view.to_h } if agent_run_already_produced?

    errors = combined_errors
    return { response_action: "errors", errors: errors } if errors.present?

    owner_result = CreateUserFromSlack.call(organization: organization, slack_user_id: owner_slack_id)
    return error("owner_block", "Couldn't resolve the selected owner. Please try again.") unless owner_result.success?

    creator = CreateUserFromSlack.call(organization: organization, slack_user_id: user_id).user
    return error("title_block", "Couldn't identify who's creating this initiative. Please try again.") if creator.nil?

    initiative = create_initiative(creator, owner_result.user)
    return error("title_block", "Something went wrong creating the initiative. Please try again.") if initiative.nil?

    post_initiative_display(initiative)
    trigger_agent_hook(initiative)
    { response_action: "clear" }
  end

  private

  def combined_errors
    errors = {}
    errors["goal_block"] = "Please select a goal" if goal.nil?
    errors["goal_block"] = "That goal can't take new initiatives right now" if goal && !goal.accepts_initiatives?
    errors["title_block"] = "Please enter a title" if title.blank?
    errors["owner_block"] = "Please select an owner" if owner_slack_id.blank?
    errors
  end

  def goal
    return @goal if defined?(@goal)

    @goal = organization.goals.find_by(id: goal_id)
  end

  def create_initiative(creator, owner)
    result = CreateInitiative.call(goal: goal, creator: creator, owner: owner, title: title, description: description)
    result.success? ? result.initiative : nil
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
    agent_run&.pending_tool_call&.dig("produced_initiative_id").present?
  end

  # Org-scoped so a stale/foreign initiative id never leaks another org's
  # initiative title (via its parent goal).
  def already_created_view
    initiative_id = agent_run.pending_tool_call["produced_initiative_id"]
    Slack::Views::InitiativeAlreadyCreatedModal.new(
      initiative: Initiative.joins(:goal).where(goals: { organization_id: organization.id }).find_by(id: initiative_id),
    )
  end

  # Best-effort: the Initiative is already committed by the time we post, so a
  # failed Slack request must not raise out of #call — that would deny Slack
  # the clear response and leave the (successfully persisted) submission open
  # for a retry. Report it and move on; the idempotency guard covers any retry.
  def post_initiative_display(initiative)
    return if display_channel_id.blank?

    Slack::Request::SendMessage.new(organization.slack_workspace).send_message(
      display_channel_id,
      Slack::Messages::InitiativeDisplay.new(initiative: initiative).to_h.merge(thread_ts: display_thread_ts),
    )
  rescue => e
    Bugsnag.notify(e, { initiative_id: initiative.id })
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
  # (resolve-once rule), so we narrate the outcome back in as a fresh turn
  # instead of resuming a run that no longer expects this tool result. Either
  # way, stamp produced_initiative_id onto the run first: a replayed
  # submission is caught by #agent_run_already_produced? at the top of #call,
  # before a second Initiative (or a second enqueue) is ever created.
  def trigger_agent_hook(initiative)
    run = agent_run
    return if run.nil?

    mark_produced(run, initiative)

    if run.status_paused_on_tool? && run.pending_tool_call&.dig("name") == "show_initiative_create_form"
      AgentResumeJob.perform_later(agent_run_id: run.id, slack_user_id: user_id, tool_result: tool_result_for(initiative))
    else
      enqueue_late_submit_event(run, initiative)
    end
  end

  # Merge-don't-overwrite, same discipline as Ai::Agent::Tools::ShowInitiativeCreateForm
  # #persist_draft and Ai::Agent::Runner#record_pending_tool_call — pending_tool_call
  # already carries "id"/"name"/"args" and those must survive this update.
  def mark_produced(run, initiative)
    pending = (run.pending_tool_call || {}).stringify_keys
    pending["produced_initiative_id"] = initiative.id
    run.update!(pending_tool_call: pending)
  end

  def tool_result_for(initiative)
    {
      status: "created",
      initiative: {
        id: initiative.id,
        title: initiative.title,
        goal_id: initiative.goal_id,
        owner: initiative.owner&.full_name,
        status: initiative.status
      }
    }
  end

  def enqueue_late_submit_event(run, initiative)
    conversation = run.conversation

    AgentTurnJob.perform_later(
      slack_team_id: organization.slack_workspace.identifier,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      surface: conversation.surface,
      slack_user_id: user_id,
      event: "user has now submitted the previously displayed initiative form; " \
             "initiative '#{initiative.title}' was created (id #{initiative.id}).",
    )
  end
end
