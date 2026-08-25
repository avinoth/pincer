module Ai
  module Agent
    module Tools
      class ShowGoal < Base
        description "Show one goal as a rich Slack detail card — progress bar, pace verdict, " \
                    "initiatives, owners — by id. Use this whenever the user wants to *see* a " \
                    "goal; never re-list its detail as markdown/a table afterwards."

        param :goal_id, type: "integer", desc: "The goal's id, as returned by list_goals or show_goals."

        def execute(goal_id:)
          goal = context.organization.goals.find_by(id: goal_id)
          return { error: "No goal found with id #{goal_id}." } unless goal

          post_detail_card(goal)

          { posted: true }.merge(GetGoal.new(context).execute(goal_id: goal.id))
        rescue StandardError => e
          { error: "Couldn't show goal #{goal_id}: #{e.message}" }
        end

        private

        def post_detail_card(goal)
          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end
      end
    end
  end
end
