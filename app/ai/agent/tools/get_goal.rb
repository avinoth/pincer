# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Full detail on a single goal: everything list_goals summarizes, plus
      # description, full metric range, initiatives (with owner names, or
      # "unassigned"), child goals, and parent. Scoped to the current
      # organization — a goal_id from another org is treated as not found.
      class GetGoal < Base
        description "Get full detail on one goal by id: description, metric progress, " \
                    "initiatives (with owners), child goals, and parent goal."

        param :goal_id, type: "integer", desc: "The goal's id, as returned by list_goals."

        def execute(goal_id:)
          goal = context.organization.goals.find_by(id: goal_id)
          return { error: "No goal found with id #{goal_id}." } unless goal

          {
            id: goal.id,
            title: goal.title,
            description: goal.description,
            start_date: goal.start_date,
            end_date: goal.end_date,
            status: goal.status,
            publishing_status: goal.publishing_status,
            health: goal.health,
            owners: goal.owners.map(&:full_name),
            metric: metric_detail(goal.metric),
            initiatives: goal.initiatives.map { |initiative| initiative_detail(initiative) },
            children: goal.sub_goals.map { |child| { id: child.id, title: child.title, status: child.status } },
            parent: goal.parent && { id: goal.parent.id, title: goal.parent.title }
          }
        rescue StandardError => e
          { error: "Couldn't load goal #{goal_id}: #{e.message}" }
        end

        private

        def metric_detail(metric)
          return nil unless metric

          {
            name: metric.name,
            start: metric.start_value,
            current: metric.current_value,
            target: metric.target_value,
            unit: metric.unit,
            direction: metric.direction
          }
        end

        def initiative_detail(initiative)
          {
            title: initiative.title,
            status: initiative.status,
            owner: initiative.owner&.full_name || "unassigned"
          }
        end
      end
    end
  end
end
