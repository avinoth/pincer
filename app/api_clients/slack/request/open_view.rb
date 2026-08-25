# frozen_string_literal: true

# Transport for Slack views (App Home + modals). Like the rest of the factory it
# takes a workspace and gets an auto-refreshed, token'd client from the Base.
# `view` may be a hash or any object responding to #to_h (e.g. Slack::Views::*).
class Slack::Request::OpenView < Slack::Request::Base
  def open_modal(view, trigger_id)
    payload = { trigger_id: trigger_id, view: to_view(view) }
    log_slack_call("views.open", payload) { client.views_open(payload) }
  rescue => e
    Bugsnag.notify(e, { workspace_id: @workspace.id, trigger_id: trigger_id })
    nil
  end

  # Update an open modal in place. Target it by `view_id` when you have it, or by
  # the `external_id` stamped on the view when you don't — e.g. a view opened via a
  # view_submission `response_action: push` (Slack never returns that view's id, so
  # external_id is the only handle a later background job has).
  def update_view(view, view_id: nil, external_id: nil)
    payload = { view: to_view(view) }
    payload[:view_id] = view_id if view_id
    payload[:external_id] = external_id if external_id
    log_slack_call("views.update", payload) { client.views_update(payload) }
  rescue => e
    Bugsnag.notify(e, { workspace_id: @workspace.id, view_id: view_id, external_id: external_id })
    nil
  end

  def publish_view(view, user_slack_id)
    payload = { user_id: user_slack_id, view: to_view(view) }
    log_slack_call("views.publish", payload) { client.views_publish(payload) }
  rescue => e
    Bugsnag.notify(e, { workspace_id: @workspace.id, user_id: user_slack_id })
    nil
  end

  private

  def to_view(view)
    view.respond_to?(:to_h) ? view.to_h : view
  end
end
