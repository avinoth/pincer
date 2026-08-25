# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Applies a direct edit to one goal's scalar fields — title, description,
      # dates, update channel, and summary schedule. Mutates immediately, no
      # confirmation pause: the refreshed GoalDisplay card, posted fresh into
      # the thread, carries the Edit button as the built-in override/undo
      # affordance (unlike show_goal_create_form, this never returns PENDING).
      #
      # Scoped to the current organization — a goal_id from another org is
      # treated as not found. Gated on Goal#modifiable_by? — only the goal's
      # creator or an owner may edit it. `status` is derived from start_date
      # (via UpdateGoal -> GoalLifecycle) and can't be set directly. Owners,
      # parent goal, and metric are NOT editable here (v1 scope) — apply what
      # you can, then point the user at the Edit button on the card.
      class EditGoal < Base
        # Slack channel mention as it appears in message text, e.g.
        # "<#C012AB|growth>" or the bare "<#C012AB>" — captures the id.
        CHANNEL_MENTION_PATTERN = /\A<#([CG][A-Z0-9]+)(?:\|[^>]*)?>\z/
        # A bare Slack channel/group id, e.g. "C012AB34".
        CHANNEL_ID_PATTERN = /\A[CG][A-Z0-9]+\z/

        description "Apply a direct edit to one goal's title, description, start/end dates, " \
                    "update channel, or summary schedule. Mutates immediately — no confirmation " \
                    "step. Requires a concrete goal_id (use list_goals, get_goal, or pick_goal to " \
                    "resolve one first, if the user's reference is ambiguous). status is derived " \
                    "from start_date and can't be set directly. Owners, parent goal, and metric " \
                    "are NOT supported here — apply what you can, then tell the user to tap Edit " \
                    "on the goal card to finish those changes."

        param :goal_id, type: "integer", desc: "The goal's id, as returned by list_goals, get_goal, or pick_goal."
        param :title, required: false, desc: "New title."
        param :description, required: false, desc: "New description."
        param :start_date, required: false, desc: "ISO8601 date (YYYY-MM-DD)."
        param :end_date, required: false, desc: "ISO8601 date (YYYY-MM-DD)."
        param :update_channel, required: false,
              desc: "The target channel's Slack id (e.g. C012AB34), taken from the user's <#...> " \
                    "channel mention. If the user names a channel without mentioning it, ask them " \
                    "to mention it with # so Slack provides the id — don't guess an id."
        param :summary_day, type: "integer", required: false,
              desc: "Day of week for the summary post, 0 (Sunday) through 6 (Saturday)."
        param :summary_time, required: false, desc: "Time of day for the summary post, 24h HH:MM."

        def execute(goal_id:, title: nil, description: nil, start_date: nil, end_date: nil,
                    update_channel: nil, summary_day: nil, summary_time: nil)
          goal = context.organization.goals.find_by(id: goal_id)
          return { error: "No goal found with id #{goal_id}." } unless goal
          unless goal.modifiable_by?(context.user&.provider_uid)
            return { error: "Only the goal's owners or creator can edit it." }
          end

          if update_channel.present?
            normalized_channel = normalize_channel(update_channel)
            unless normalized_channel
              return {
                error: "\"#{update_channel}\" doesn't look like a channel — ask the user to mention " \
                       "it with # so Slack gives me its id."
              }
            end
            update_channel = normalized_channel
          end

          attributes = {
            title: title,
            description: description,
            start_date: start_date,
            end_date: end_date,
            update_channel: update_channel,
            summary_day: summary_day,
            summary_time: summary_time
          }.compact

          result = UpdateGoal.call(goal: goal, attributes: attributes, publish: false)
          return { error: result.error } if result.failure?

          post_goal_display(result.goal)
          success_result(result.goal, attributes.keys)
        rescue StandardError => e
          { error: "Couldn't edit goal #{goal_id}: #{e.message}" }
        end

        private

        # Accepts a Slack channel mention token (defensive — in case the model
        # passes the whole "<#C012AB|growth>" instead of extracting the id
        # itself) or a bare channel/group id. Returns the normalized id, or nil
        # if the value doesn't look like a real Slack channel id at all (e.g. a
        # bare name like "growth") — that's the case we must not silently store.
        def normalize_channel(value)
          match = CHANNEL_MENTION_PATTERN.match(value)
          candidate = match ? match[1] : value
          candidate if CHANNEL_ID_PATTERN.match?(candidate)
        end

        def post_goal_display(goal)
          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end

        def success_result(goal, changed_fields)
          {
            id: goal.id,
            title: goal.title,
            changed_fields: changed_fields,
            start_date: goal.start_date,
            end_date: goal.end_date,
            status: goal.status,
            note: "Owners, parent goal, and metric changes require the Edit button on the goal card."
          }
        end
      end
    end
  end
end
