# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Records a new reported value for a goal's metric — an append-only
      # MetricUpdate, Metric#current_value advanced to match, and a
      # GoalUpdate(kind: metric) log entry — via the RecordMetricUpdate
      # interactor, then re-posts the refreshed GoalDisplay card.
      #
      # Scoped to the current organization — a goal_id from another org is
      # treated as not found. Gated on Goal#modifiable_by? (same rule as
      # edit_goal): only the goal's creator or an owner may report a value.
      # Note: this freezes the metric's definition (name/direction/target) —
      # the existing "no editing a metric once any MetricUpdate exists" rule —
      # which is intended, not a bug to work around.
      class RecordMetricUpdate < Base
        description "Record a new reported value for a goal's metric — advances current_value and " \
                    "logs it to the goal's timeline. Requires a concrete goal_id (use list_goals, " \
                    "get_goal, or pick_goal to resolve one first if the user's reference is " \
                    "ambiguous). Only for goals that already have a metric. If the user's message " \
                    "is answering a specific open check-in, pass its checkin_id (from \"your open " \
                    "check-ins\" context) so this report links back to it."

        param :goal_id, type: "integer", desc: "The goal's id, as returned by list_goals, get_goal, or pick_goal."
        param :value, type: "number", desc: "The new metric value, as a plain number (no currency symbol or % sign)."
        param :note, required: false, desc: "Optional free-text context for this value, e.g. \"paused campaign this week\"."
        param :checkin_id, type: "integer", required: false,
              desc: "The id of the open check-in this report answers, if shown in \"your open check-ins\" context."

        def execute(goal_id:, value:, note: nil, checkin_id: nil)
          goal = context.organization.goals.find_by(id: goal_id)
          return { error: "No goal found with id #{goal_id}." } unless goal

          metric = goal.metric
          return { error: "Goal #{goal_id} (\"#{goal.title}\") has no metric to report a value for." } unless metric

          unless goal.modifiable_by?(context.user&.provider_uid)
            return { error: "Only the goal's owners or creator can report a metric value." }
          end

          result = ::RecordMetricUpdate.call(
            metric: metric, value: value, note: note, reported_by: context.user,
            checkin: find_checkin(goal, checkin_id),
          )
          return { error: result.error } if result.failure?

          post_goal_display(goal.reload)
          success_result(goal, metric.reload, result.metric_update)
        rescue StandardError => e
          { error: "Couldn't record a metric update for goal #{goal_id}: #{e.message}" }
        end

        private

        def find_checkin(goal, checkin_id)
          return nil if checkin_id.blank? || context.user.blank?

          context.user.checkins.find_by(id: checkin_id, goal_id: goal.id)
        end

        def post_goal_display(goal)
          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end

        def success_result(goal, metric, metric_update)
          {
            goal_id: goal.id,
            metric_name: metric.name,
            value: metric_update.value,
            current_value: metric.current_value,
            target_value: metric.target_value
          }
        end
      end
    end
  end
end
