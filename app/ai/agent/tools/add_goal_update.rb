# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Logs a free-text note against a goal (optionally scoped to one of its
      # initiatives) via the AddGoalUpdate interactor, then re-posts the
      # refreshed GoalDisplay card. For context/color that isn't a metric value
      # or an initiative status change — use record_metric_update or
      # update_initiative_status for those instead.
      #
      # Scoped to the current organization — a goal_id from another org is
      # treated as not found. Authorization is broader than the other two
      # tools: the goal's owner/creator, OR the owner of ANY initiative on
      # that goal, may leave a note (see AddGoalUpdate).
      class AddGoalUpdate < Base
        description "Log a free-text note on a goal's timeline (optionally scoped to one of its " \
                    "initiatives) — for color/context that isn't a metric value or an initiative " \
                    "status change. Requires a concrete goal_id. If the user's message is " \
                    "answering a specific open check-in, pass its checkin_id (from \"your open " \
                    "check-ins\" context) so this note links back to it."

        param :goal_id, type: "integer", desc: "The goal's id, as returned by list_goals, get_goal, or pick_goal."
        param :body, desc: "The note, written plainly in the user's own words."
        param :initiative_id, type: "integer", required: false,
              desc: "Scope the note to one of the goal's initiatives, if the user was talking about a specific one."
        param :checkin_id, type: "integer", required: false,
              desc: "The id of the open check-in this note answers, if shown in \"your open check-ins\" context."

        def execute(goal_id:, body:, initiative_id: nil, checkin_id: nil)
          goal = context.organization.goals.find_by(id: goal_id)
          return { error: "No goal found with id #{goal_id}." } unless goal

          initiative = find_initiative(goal, initiative_id)
          return { error: "No initiative found with id #{initiative_id} on that goal." } if initiative_id && !initiative

          result = ::AddGoalUpdate.call(
            goal: goal, body: body, initiative: initiative, reported_by: context.user,
            checkin: find_checkin(goal, checkin_id),
          )
          return { error: result.error } if result.failure?

          post_goal_display(goal.reload)
          success_result(result.goal_update)
        rescue StandardError => e
          { error: "Couldn't add a note to goal #{goal_id}: #{e.message}" }
        end

        private

        def find_initiative(goal, initiative_id)
          return nil if initiative_id.blank?

          goal.initiatives.find_by(id: initiative_id)
        end

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

        def success_result(goal_update)
          { goal_update_id: goal_update.id, body: goal_update.body, initiative_id: goal_update.initiative_id }
        end
      end
    end
  end
end
