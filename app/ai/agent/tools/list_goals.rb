# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Lists the organization's goals as compact, LLM-friendly summaries —
      # enough to answer "how are we doing?" or "what's due this quarter?"
      # without a second round trip. Call get_goal for full detail on one goal.
      class ListGoals < Base
        description "List the organization's goals, optionally filtered by a date-range " \
                    "overlap, lifecycle status, publishing status, or owner. Returns compact " \
                    "summaries (not full detail — use get_goal for that)."

        param :start_date, required: false,
              desc: "ISO8601 date. Together with end_date, filters to goals whose own dates " \
                    "overlap this period (e.g. a quarter's start/end)."
        param :end_date, required: false, desc: "ISO8601 date. See start_date."
        param :status, required: false, desc: "Lifecycle status: not_started, in_progress, completed, ended."
        param :publishing_status, required: false, desc: "\"draft\" or \"published\"."
        # TODO: Potentially add a tool to get the user first
        param :owner, required: false,
              desc: "A Slack user id or a name fragment; loosely matched against organization members."

        def execute(start_date: nil, end_date: nil, status: nil, publishing_status: nil, owner: nil)
          goals = context.organization.goals.includes(:owners, :metric, :initiatives, :sub_goals)
          goals = filter_by_period(goals, start_date, end_date)
          goals = goals.where(status: status) if status.present?
          goals = goals.where(publishing_status: publishing_status) if publishing_status.present?
          goals = filter_by_owner(goals, owner)

          goals.map { |goal| summarize(goal) }
        rescue StandardError => e
          { error: "Couldn't list goals: #{e.message}" }
        end

        private

        # Overlap semantics: a goal is in-period if it hasn't ended before the
        # period starts, and hasn't started after the period ends. Either bound
        # may be given alone (an open-ended filter).
        def filter_by_period(goals, start_date, end_date)
          goals = goals.where("end_date >= ?", start_date) if start_date.present?
          goals = goals.where("start_date <= ?", end_date) if end_date.present?
          goals
        end

        def filter_by_owner(goals, owner)
          return goals if owner.blank?

          user = resolve_owner(owner)
          return goals.none unless user

          goals.where(id: GoalOwner.where(user: user).select(:goal_id))
        end

        def resolve_owner(owner)
          scope = context.organization.users
          scope.where(provider_uid: owner).or(scope.where("full_name ILIKE ?", "%#{owner}%")).first
        end

        def summarize(goal)
          {
            id: goal.id,
            title: goal.title,
            start_date: goal.start_date,
            end_date: goal.end_date,
            status: goal.status,
            publishing_status: goal.publishing_status,
            health: goal.health,
            owners: goal.owners.map(&:full_name),
            metric: metric_summary(goal.metric),
            initiatives: {
              total: goal.initiatives.size,
              unassigned: goal.initiatives.count { |i| i.owner_id.nil? }
            },
            child_goal_count: goal.sub_goals.size
          }
        end

        def metric_summary(metric)
          return nil unless metric

          { name: metric.name, current: metric.current_value, target: metric.target_value, unit: metric.unit }
        end
      end
    end
  end
end
