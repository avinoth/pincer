class Slack::EventsController < ApplicationController
  # Human-readable handle we substitute for the bot's own "<@BOT_UID>" mention so
  # the agent (and transcript) sees who was addressed instead of an opaque Slack
  # id.
  BOT_HANDLE = "@pincer"

  # Slack signs every request; reject anything that fails verification.
  before_action :verify_slack_signature
  # Log every (verified) inbound payload — events, interactions, commands,
  # options, url_verification — from this one seam, so "all inbound" needs no
  # per-type wiring. Runs after verification so forged requests aren't recorded.
  before_action :log_inbound_interaction

  # POST /slack/events — Events API callbacks AND interactive payloads. The app
  # manifest points both event_subscriptions and interactivity at this URL, so
  # button clicks / modal submits arrive here as a `payload` param rather than as
  # an Events API `event`.
  def create
    return render(json: { challenge: params[:challenge] }) if params[:type] == "url_verification"
    return route_interaction if params[:payload].present?

    # The invoking user is provisioned downstream (off this request's ack path) by
    # the enqueued job via CreateUserFromSlack, so we never block the 3s ack.
    dispatch_event
    head :ok
  end

  # POST /slack/interactions — dedicated interactivity endpoint (kept in case the
  # Slack app is configured to post interactions here instead of /slack/events).
  def interactions
    return head(:bad_request) if params[:payload].blank?

    route_interaction
  end

  # POST /slack/command — slash commands. STUB SEAM (verified, acknowledged).
  def command
    # LATER: route to Command::Slack and reply. Ack within 3s per Slack's contract.
    head :ok
  end

  # POST /slack/options_for_select — external select menus. STUB SEAM.
  def options_for_select
    render json: { options: [] }
  end

  private

  # Routes an interactive payload (button click, modal submit) through the
  # interaction router. view_submission handlers may return a response_action
  # hash to render; everything else just acks with 200.
  def route_interaction
    result = Slack::Interactions::Router.new(JSON.parse(params[:payload])).route
    result.is_a?(Hash) ? render(json: result) : head(:ok)
  rescue JSON::ParserError
    head :bad_request
  end

  def dispatch_event
    event = params[:event] || {}

    case event[:type]
    when "app_uninstalled"
      handle_app_uninstalled
    when "app_mention"
      handle_app_mention(event)
    when "app_home_opened"
      # STUB SEAM — App Home UX not yet specified.
      AppHomeDisplayJob.perform_later(event[:user], params[:team_id])
    when "team_join"
      handle_team_join(event)
    when "message"
      handle_message(event)
    when "assistant_thread_started"
      handle_assistant_thread_started(event)
    when "assistant_thread_context_changed"
      handle_assistant_thread_context_changed(event)
    else
      # Unhandled event type — acknowledged with 200 so Slack doesn't retry.
    end
  end

  def handle_app_uninstalled
    organization = organization_for(params[:team_id])
    organization&.inactive!
  end

  # Bot was @-mentioned → hand the turn to the agent (channel surface),
  # asynchronously. Slack must be acked within 3s so this only enqueues.
  def handle_app_mention(event)
    return if event[:bot_id].present? # ignore bot/self mentions

    organization = organization_for(params[:team_id])
    return unless organization

    AgentTurnJob.perform_later(
      slack_team_id: params[:team_id],
      channel: event[:channel],
      thread_ts: event[:thread_ts] || event[:ts],
      surface: "channel",
      slack_user_id: event[:user],
      text: clean_mention_text(event[:text], organization.slack_workspace&.bot_uid),
    )
  end

  # Strips the bot's own "<@BOT_UID>" mention out of the raw event text so the
  # agent (and the persisted transcript) sees "@pincer" instead of an opaque
  # Slack id.
  def clean_mention_text(text, bot_uid)
    return text.to_s.strip if bot_uid.blank?

    text.to_s.gsub(/<@#{Regexp.escape(bot_uid)}>/, BOT_HANDLE).strip
  end

  # New member joined the Slack workspace → provision their User row now,
  # rather than waiting for their first interaction with the bot.
  def handle_team_join(event)
    return if event[:user].blank?

    ProcessTeamJoinJob.perform_later(team_id: params[:team_id], user: event[:user].to_unsafe_h)
  end

  def handle_message(event)
    # Ignore the bot's own messages and system subtypes.
    return if event[:bot_id].present? || event[:subtype].present?

    route_message(event)
  end

  # A direct message to the bot → hand the turn to the agent as well. Only 1:1
  # DMs (im) fire without a mention; group DMs (mpim) rely on app_mention, and
  # channel messages are ignored.
  def route_message(event)
    return unless event[:channel_type] == "im"

    organization = organization_for(params[:team_id])
    return unless organization

    AgentTurnJob.perform_later(
      slack_team_id: params[:team_id],
      channel: event[:channel],
      thread_ts: event[:thread_ts] || event[:ts],
      surface: message_surface(organization, event),
      slack_user_id: event[:user],
      text: event[:text],
    )
  end

  # A message.im event fires for BOTH plain DMs and messages typed into a Slack
  # Agent split-view thread — Slack gives no definitive per-message flag for
  # which. Most robust rule available: if we already have a Conversation for
  # this (org, channel, thread_ts), its surface is authoritative (it was set
  # when the thread was first seen — e.g. by assistant_thread_started). Only for
  # a thread we've never seen do we fall back to the event's own
  # `assistant_thread` marker (present on messages Slack delivers inside an
  # assistant container); absent that too, it's a plain DM.
  def message_surface(organization, event)
    channel = event[:channel]
    thread_ts = event[:thread_ts] || event[:ts]
    existing = organization.conversations.find_by(slack_channel_id: channel, slack_thread_ts: thread_ts)
    return existing.surface if existing

    event[:assistant_thread].present? ? "assistant" : "dm"
  end

  # assistant_thread_started fires once, when the user opens a fresh Agent
  # split-view thread (before they've typed anything). Greet them and seed the
  # thread's suggested prompts, off the ack path.
  def handle_assistant_thread_started(event)
    thread = event[:assistant_thread] || {}

    AssistantThreadStartedJob.perform_later(
      slack_team_id: params[:team_id],
      channel: thread[:channel_id],
      thread_ts: thread[:thread_ts],
      slack_user_id: thread[:user_id],
      context: (thread[:context] || {}).to_unsafe_h,
    )
  end

  # assistant_thread_context_changed fires when the user switches which channel
  # they're viewing while the split-view thread stays open. No agent run — just
  # keep the Conversation's context hint current for the next turn's prompt.
  def handle_assistant_thread_context_changed(event)
    thread = event[:assistant_thread] || {}

    AssistantThreadContextChangedJob.perform_later(
      slack_team_id: params[:team_id],
      channel: thread[:channel_id],
      thread_ts: thread[:thread_ts],
      context: (thread[:context] || {}).to_unsafe_h,
    )
  end

  def organization_for(team_id)
    SlackWorkspace.find_by(identifier: team_id)&.organization
  end

  # Enqueues the raw posted body for logging off the ack path. request_parameters
  # is the parsed request body only (no route/query params, no wrap-params
  # duplication): an events JSON hash, or { "payload" => "<json>" } for
  # interactive/options payloads, or the form fields for a slash command. The job
  # extracts identity and resolves the org. Never break the ack path on a log error.
  def log_inbound_interaction
    LogSlackInteractionJob.perform_later(
      direction: "inbound",
      slack_params: request.request_parameters,
      retry_num: request.headers["X-Slack-Retry-Num"],
      retry_reason: request.headers["X-Slack-Retry-Reason"],
    )
  rescue => e
    Bugsnag.notify(e)
  end

  def verify_slack_signature
    head :unauthorized unless slack_request_valid?
  end

  # HMAC-SHA256 verification per https://api.slack.com/authentication/verifying-requests-from-slack
  def slack_request_valid?
    timestamp = request.headers["X-Slack-Request-Timestamp"]
    signature = request.headers["X-Slack-Signature"]
    secret = ENV["SLACK_SIGNING_SECRET"]

    return false if timestamp.blank? || signature.blank? || secret.blank?
    return false if (Time.now.to_i - timestamp.to_i).abs > 300 # 5-minute replay window

    basestring = "v0:#{timestamp}:#{request.raw_post}"
    expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, basestring)}"

    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
