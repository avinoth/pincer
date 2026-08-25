# frozen_string_literal: true

# Persists one SlackInteraction row for an inbound Slack payload or an outbound
# conversational Web API call. Runs async (off the 3s ack path and off the
# interactive request path); the raw payload rides along as durable job args.
#
# Logging must never take down a request or another job, so any failure here is
# swallowed to Bugsnag rather than raised.
class LogSlackInteractionJob < ApplicationJob
  queue_as :default

  def perform(direction:, slack_params: nil, api_method: nil, team_id: nil,
    request_payload: nil, response: nil, ok: nil, error: nil,
    retry_num: nil, retry_reason: nil)
    attributes =
      if direction.to_s == "outbound"
        outbound_attributes(api_method:, team_id:, request_payload:, response:, ok:, error:)
      else
        inbound_attributes(slack_params || {}, retry_num:, retry_reason:)
      end

    SlackInteraction.create!(attributes)
  rescue => e
    Bugsnag.notify(e, { slack_interaction_direction: direction })
    nil
  end

  private

  # Normalizes the three inbound shapes (Events API callback, interactive
  # payload, slash command) plus anything else (url_verification, …) into a row.
  def inbound_attributes(raw, retry_num:, retry_reason:)
    raw = raw.with_indifferent_access
    kind = inbound_kind(raw)

    ident = inbound_identity(kind, raw)

    {
      direction: "inbound",
      event_type: ident[:event_type],
      team_id: ident[:team_id],
      organization_id: organization_id_for(ident[:team_id]),
      channel_id: ident[:channel_id],
      slack_user_id: ident[:slack_user_id],
      ts: ident[:ts],
      thread_ts: ident[:thread_ts],
      payload: ident[:stored],
      retry_num: retry_num.presence,
      retry_reason: retry_reason.presence
    }
  end

  def inbound_kind(raw)
    return :interactive if raw[:payload].present?
    return :event if raw[:event].present?
    return :command if raw[:command].present?

    :other
  end

  def inbound_identity(kind, raw)
    case kind
    when :interactive
      p = interactive_payload(raw)
      {
        event_type: p[:type],
        team_id: p.dig(:team, :id),
        channel_id: p.dig(:channel, :id) || p.dig(:container, :channel_id),
        slack_user_id: p.dig(:user, :id),
        ts: p.dig(:message, :ts) || p.dig(:container, :message_ts),
        # A message that isn't in a thread has no thread_ts; fall back to its own
        # ts so every row in a conversation shares one thread_ts (matches Wave and
        # the outbound reply, which is posted with thread_ts = the root ts).
        thread_ts: p.dig(:message, :thread_ts) || p.dig(:message, :ts) || p.dig(:container, :message_ts),
        stored: p
      }
    when :event
      e = raw[:event]
      {
        event_type: e[:type],
        team_id: raw[:team_id],
        channel_id: e[:channel],
        slack_user_id: e[:user],
        ts: e[:ts],
        # Root messages arrive with thread_ts nil; normalise to the message's own
        # ts (as handle_app_mention does) so the root shares a thread_ts with the
        # bot's threaded replies and in_thread reconstructs the full conversation.
        thread_ts: e[:thread_ts] || e[:ts],
        stored: raw
      }
    when :command
      {
        event_type: "slash_command",
        team_id: raw[:team_id],
        channel_id: raw[:channel_id],
        slack_user_id: raw[:user_id],
        ts: nil,
        thread_ts: nil,
        stored: raw
      }
    else
      { event_type: raw[:type], team_id: raw[:team_id], stored: raw }
    end
  end

  def interactive_payload(raw)
    JSON.parse(raw[:payload]).with_indifferent_access
  rescue JSON::ParserError, TypeError
    {}.with_indifferent_access
  end

  def outbound_attributes(api_method:, team_id:, request_payload:, response:, ok:, error:)
    req = (request_payload || {}).with_indifferent_access
    resp = (response || {}).with_indifferent_access

    {
      direction: "outbound",
      event_type: api_method,
      team_id: team_id,
      organization_id: organization_id_for(team_id),
      channel_id: resp[:channel] || req[:channel],
      ts: resp[:ts] || req[:ts],
      thread_ts: req[:thread_ts],
      payload: req,
      response: response,
      ok: ok,
      error: error
    }
  end

  def organization_id_for(team_id)
    return if team_id.blank?

    SlackWorkspace.find_by(identifier: team_id)&.organization_id
  end
end
