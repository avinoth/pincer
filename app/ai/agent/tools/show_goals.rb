module Ai
  module Agent
    module Tools
      class ShowGoals < Base
        description "Show the organization's goals as rich Slack cards — one colored card per " \
                    "goal, capped at #{Slack::Messages::GoalSummaryList::MAX_SUMMARY_CARDS} — " \
                    "optionally filtered by a date-range overlap, lifecycle status, publishing " \
                    "status, or owner. Use this whenever the user wants to *see* their goals; " \
                    "never re-list them as markdown/a table afterwards."

        param :start_date, required: false,
              desc: "ISO8601 date. Together with end_date, filters to goals whose own dates " \
                    "overlap this period (e.g. a quarter's start/end)."
        param :end_date, required: false, desc: "ISO8601 date. See start_date."
        param :status, required: false, desc: "Lifecycle status: not_started, in_progress, completed, ended."
        param :publishing_status, required: false, desc: "\"draft\" or \"published\"."
        param :owner, required: false,
              desc: "A Slack user id or a name fragment; loosely matched against organization members."

        def execute(start_date: nil, end_date: nil, status: nil, publishing_status: nil, owner: nil)
          scope = context.organization.goals.includes(:owners, :metric, :initiatives)
          scope = filter_by_period(scope, start_date, end_date)
          scope = scope.where(status: status) if status.present?
          scope = scope.where(publishing_status: publishing_status) if publishing_status.present?
          scope = filter_by_owner(scope, owner)

          total = scope.count
          goals = sorted(scope).limit(Slack::Messages::GoalSummaryList::MAX_SUMMARY_CARDS).to_a

          post_summary_list(goals, total)

          { posted: true, shown: goals.size, total: total, goals: goals.map { |goal| summarize(goal) } }
        rescue StandardError => e
          { error: "Couldn't show goals: #{e.message}" }
        end

        private

        def sorted(scope)
          scope.order(Arel.sql(<<~SQL.squish)).order(:end_date)
            CASE status
              WHEN 'in_progress' THEN 0
              WHEN 'not_started' THEN 1
              WHEN 'completed' THEN 2
              ELSE 3
            END
          SQL
        end

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

        def post_summary_list(goals, total)
          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            Slack::Messages::GoalSummaryList.new(goals: goals, total: total).to_h
              .merge(thread_ts: context.conversation.slack_thread_ts),
          )
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
            metric: metric_summary(goal.metric)
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
