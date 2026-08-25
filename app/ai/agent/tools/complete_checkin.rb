# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Marks one or more open Checkin rows completed, via the CompleteCheckin
      # interactor. Call this LAST, after record_metric_update /
      # update_initiative_status / add_goal_update have captured whatever the
      # check-in(s) asked for — this tool itself makes no goal/initiative
      # changes, so it never re-posts a GoalDisplay card.
      #
      # Scoped to the current turn's user: a checkin_id belonging to someone
      # else (in this org or another) is treated as not found — nobody can
      # complete another person's check-in.
      class CompleteCheckin < Base
        description "Mark one or more of the current user's open check-ins as completed. Call this " \
                    "LAST, once record_metric_update / update_initiative_status / add_goal_update " \
                    "have captured everything the check-in(s) asked for — don't call this before " \
                    "capturing the information, and don't re-ask for something already captured. " \
                    "Pass the checkin_id(s) from \"your open check-ins\" context."

        param :checkin_ids, type: "array", desc: "The id(s) of the open check-in(s) to complete."

        def execute(checkin_ids:)
          ids = Array(checkin_ids).map(&:to_i)
          return { error: "No checkin_ids given." } if ids.empty?

          checkins = context.user.checkins.where(id: ids, organization_id: context.organization.id).to_a
          missing = ids - checkins.map(&:id)
          return { error: "No open check-in found for id(s) #{missing.join(', ')}." } if checkins.empty?

          result = ::CompleteCheckin.call(checkins: checkins, user: context.user)
          return { error: result.error } if result.failure?

          { completed_checkin_ids: result.checkins.map(&:id), skipped_ids: missing }.compact
        rescue StandardError => e
          { error: "Couldn't complete check-in(s): #{e.message}" }
        end
      end
    end
  end
end
