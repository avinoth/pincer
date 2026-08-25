# frozen_string_literal: true

# Raised when a Slack access token can't be refreshed before an API call.
class Slack::Request::TokenRenewalError < StandardError; end

# Base for authenticated per-workspace Slack Web API calls. Builds a token'd
# client (auto-refreshing expired tokens) and provides Rails.cache-backed
# response caching for subclasses that opt in via `cached_request`.
class Slack::Request::Base
  def initialize(workspace)
    @workspace = workspace
    @client = nil
  end

  def client
    renew_token_if_expired!
    @client ||= Slack::Web::Client.new(token: @workspace.access_token)
  end

  def cache_response(key_to_cache, response)
    Rails.cache.write(key_to_cache, response.to_json, expires_in: cache_expiry_in_seconds)
  end

  def fetch_from_cache
    data = Rails.cache.read(cache_key)
    return if data.blank?

    JSON.parse(data)
  end

  def cached_request
    response = fetch_from_cache
    return response if response.present?

    response = make_request
    cache_response(cache_key, response)

    response
  end

  def renew_token_if_expired!
    return unless @workspace.token_expired?

    result = RenewSlackAccessToken.call(workspace: @workspace)
    raise Slack::Request::TokenRenewalError, "Failed to renew Slack access token" if result.failure?
  end

  # 15 minutes.
  def cache_expiry_in_seconds
    900
  end

  def cache_key
    raise "MUST IMPLEMENT CACHE KEY TO USE CACHE"
  end

  def make_request
    raise "MUST IMPLEMENT MAKE REQUEST"
  end

  # Wraps a conversational Slack Web API call (chat.postMessage, chat.update,
  # views_*), logging the request and its response — including the returned
  # message `ts` — as a SlackInteraction. Returns the response untouched and
  # re-raises on failure so callers' existing error handling is unaffected.
  # Logging is best-effort and enqueued async, so it never blocks the call path.
  def log_slack_call(api_method, request_payload)
    response = yield
    enqueue_outbound_log(api_method, request_payload, response: response, ok: true)
    response
  rescue => e
    enqueue_outbound_log(api_method, request_payload, ok: false, error: e.message)
    raise
  end

  def enqueue_outbound_log(api_method, request_payload, response: nil, ok: nil, error: nil)
    LogSlackInteractionJob.perform_later(
      direction: "outbound",
      api_method: api_method,
      team_id: @workspace&.identifier,
      request_payload: request_payload,
      response: response.respond_to?(:to_h) ? response.to_h : response,
      ok: ok,
      error: error,
    )
  rescue => e
    Bugsnag.notify(e)
  end
end
