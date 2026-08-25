# frozen_string_literal: true

module Ai
  module Agent
    module Schemas
      # Structured-output shape for GenerateGoalSummary's one-shot RubyLLM
      # call (chat.with_schema(GoalSummarySchema)) — used for both the weekly
      # summary and the end-of-cycle closing narrative. `health` mirrors
      # Goal#health's enum values so the interactor can write it straight
      # onto both GoalNotification#health and Goal#health.
      class GoalSummarySchema < RubyLLM::Schema
        string :health, enum: %w[on_track at_risk off_track],
          description: "Overall health classification for the period, based on progress toward the metric's target and how much of the cycle remains."
        string :body,
          description: "A plain-language narrative (a few short paragraphs) covering progress, gaps, blockers/risks, and metric status for the period. Written for a Slack channel audience."
      end
    end
  end
end
