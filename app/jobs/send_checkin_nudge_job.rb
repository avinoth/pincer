# DMs one owner a single clubbed check-in nudge covering every Checkin
# CheckinNudgeSchedulerJob created for them this tick, then wires the reply
# thread up for the agent: captures the outbound message's `ts`, stamps it (+
# the DM channel id) onto those Checkins as slack_thread_ts, flips them
# notified, and pre-creates the Conversation so AgentTurnJob finds it with
# context already attached the moment the owner replies.
class SendCheckinNudgeJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  queue_as :default

  # One send per owner at a time — overlapping ticks (or a retry) must not DM
  # the same owner twice for the same batch of checkins.
  good_job_control_concurrency_with(
    perform_limit: 1,
    key: -> { "send-checkin-nudge:#{(arguments.first || {})[:user_id]}" },
  )

  def perform(user_id:, checkin_ids:)
    user = User.find_by(id: user_id)
    return unless user

    checkins = user.checkins.status_pending.where(id: checkin_ids).to_a
    return if checkins.empty?

    workspace = user.organization.slack_workspace
    return unless workspace

    response = Slack::Request::SendMessage.new(workspace).send_message(
      user.provider_uid,
      Slack::Messages::CheckinNudge.new(checkins: checkins).to_h,
    )
    return if response.blank?

    channel_id = response[:channel]
    thread_ts = response[:ts]
    return if channel_id.blank? || thread_ts.blank?

    mark_notified(checkins, channel_id, thread_ts)
    seed_conversation(user.organization, channel_id, thread_ts, checkins)
  rescue => e
    Bugsnag.notify(e, { user_id: user_id, checkin_ids: checkin_ids })
  end

  private

  def mark_notified(checkins, channel_id, thread_ts)
    Checkin.where(id: checkins.map(&:id)).update_all(
      slack_channel_id: channel_id,
      slack_thread_ts: thread_ts,
      status: "notified",
      notified_at: Time.current,
      updated_at: Time.current,
    )
  end

  def seed_conversation(organization, channel_id, thread_ts, checkins)
    organization.conversations.create_with(
      surface: :dm,
      context_hint: context_hint_for(checkins),
    ).find_or_create_by!(slack_channel_id: channel_id, slack_thread_ts: thread_ts)
  end

  def context_hint_for(checkins)
    titles = checkins.map(&:goal).uniq.map(&:title)
    "user was just sent a weekly check-in nudge for: #{titles.join(', ')}"
  end
end
