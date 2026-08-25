# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Changes an initiative's status (e.g. marking it done) via the
      # UpdateInitiativeStatus interactor, which also logs a
      # GoalUpdate(kind: initiative_status), then re-posts the refreshed
      # GoalDisplay card for the initiative's parent goal.
      #
      # Scoped to the current organization — an initiative_id belonging to
      # another org's goal is treated as not found. Gated on
      # Initiative#modifiable_by?: the initiative's own owner, or anyone who
      # can modify its parent goal (creator/owner), may update it.
      class UpdateInitiativeStatus < Base
        description "Change an initiative's status (proposed, in_progress, done, or dropped). " \
                    "Requires a concrete initiative_id — get one from get_goal's initiatives list. " \
                    "If the user's message is answering a specific open check-in, pass its " \
                    "checkin_id (from \"your open check-ins\" context) so this update links back to it."

        param :initiative_id, type: "integer", desc: "The initiative's id, as returned by get_goal."
        param :status, desc: "New status: \"proposed\", \"in_progress\", \"done\", or \"dropped\"."
        param :checkin_id, type: "integer", required: false,
              desc: "The id of the open check-in this update answers, if shown in \"your open check-ins\" context."

        def execute(initiative_id:, status:, checkin_id: nil)
          initiative = ::Initiative.joins(:goal).merge(context.organization.goals).find_by(id: initiative_id)
          return { error: "No initiative found with id #{initiative_id}." } unless initiative

          unless initiative.modifiable_by?(context.user&.provider_uid)
            return { error: "Only the initiative's owner or the goal's owners/creator can update it." }
          end

          result = ::UpdateInitiativeStatus.call(
            initiative: initiative, status: status, reported_by: context.user,
            checkin: find_checkin(initiative, checkin_id),
          )
          return { error: result.error } if result.failure?

          post_goal_display(initiative.goal.reload)
          success_result(result.initiative)
        rescue StandardError => e
          { error: "Couldn't update initiative #{initiative_id}: #{e.message}" }
        end

        private

        def find_checkin(initiative, checkin_id)
          return nil if checkin_id.blank? || context.user.blank?

          context.user.checkins.find_by(id: checkin_id, initiative_id: initiative.id)
        end

        def post_goal_display(goal)
          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end

        def success_result(initiative)
          { initiative_id: initiative.id, title: initiative.title, status: initiative.status }
        end
      end
    end
  end
end
