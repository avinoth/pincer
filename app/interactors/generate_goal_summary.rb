# Generates the LLM narrative shared by the weekly summary and the end-of-cycle
# closing notification. A one-shot RubyLLM structured-output completion — no
# tools, no Conversation/AgentRun/streaming, just goal:, a window, and a mode.
# Reuses the same model config as the Slack agent
# (Rails.application.config.x.ai_models.fetch(:agent), OpenRouter).
#
# Context in:  goal (Goal), period_start (Date/Time), period_end (Date/Time),
#              mode (:weekly | :end).
# Context out: health (String, one of Goal::HEALTHS), body (String, the
#              narrative).
class GenerateGoalSummary
  include Interactor

  PROVIDER = "openrouter"

  def call
    goal = context.goal
    return context.fail!(error: "goal is required") if goal.nil?

    response = chat.with_schema(Ai::Agent::Schemas::GoalSummarySchema).ask(prompt(goal))
    payload = response.content.is_a?(Hash) ? response.content.stringify_keys : {}

    context.health = payload["health"]
    context.body = payload["body"]

    context.fail!(error: "LLM returned no body") if context.body.blank?
  rescue StandardError => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end

  private

  def chat
    RubyLLM.chat(
      model: resolved_model,
      provider: PROVIDER.to_sym,
      assume_model_exists: assume_model_exists?,
    ).with_temperature(0.4)
  end

  def resolved_model
    Rails.application.config.x.ai_models.fetch(:agent)
  end

  def assume_model_exists?
    Rails.application.config.x.ai_assume_model_exists
  end

  # --- Prompt construction --------------------------------------------------

  def prompt(goal)
    <<~PROMPT
      #{framing}

      #{goal_section(goal)}
      #{metric_section(goal)}
      #{updates_section(goal)}
      #{metric_updates_section(goal)}
      #{expired_checkins_section(goal)}

      Write a plain-language narrative covering what progressed, what didn't,
      any blockers or risks, and where the metric stands relative to its
      target. Classify the overall health as on_track, at_risk, or off_track,
      weighing how much of the cycle remains against the progress made.
    PROMPT
  end

  def framing
    if context.mode.to_sym == :end
      "You are writing the final, closing summary for a goal whose cycle has just ended — covering its entire run from start to end, not just the last period."
    else
      "You are writing this week's summary for an in-progress goal, covering only the period below."
    end
  end

  def goal_section(goal)
    <<~TEXT
      Goal: #{goal.title}
      #{"Description: #{goal.description}" if goal.description.present?}
      Cycle: #{goal.start_date} to #{goal.end_date}
      Period covered by this summary: #{context.period_start} to #{context.period_end}
    TEXT
  end

  def metric_section(goal)
    metric = goal.metric
    return "Metric: none" if metric.nil?

    <<~TEXT
      Metric: #{metric.name} (#{metric.direction}) — currently #{metric.formatted_current_value}, target #{metric.formatted_target_value}
    TEXT
  end

  def updates_section(goal)
    updates = goal.goal_updates.where(created_at: window).order(:created_at)
    return "Updates logged this period: none" if updates.empty?

    lines = updates.map { |u| "- [#{u.kind}] #{u.reported_by&.full_name}: #{u.body}" }
    "Updates logged this period:\n#{lines.join("\n")}"
  end

  def metric_updates_section(goal)
    return "" if goal.metric.nil?

    metric_updates = goal.metric.metric_updates.where(created_at: window).order(:created_at)
    return "Metric values reported this period: none" if metric_updates.empty?

    lines = metric_updates.map { |mu| "- #{mu.reported_by&.full_name}: #{Metric.format_value(mu.value, goal.metric.unit)}#{" — #{mu.note}" if mu.note.present?}" }
    "Metric values reported this period:\n#{lines.join("\n")}"
  end

  def expired_checkins_section(goal)
    expired = goal.checkins.status_expired.where(created_at: window).order(:created_at)
    return "Unanswered check-ins (gaps) this period: none" if expired.empty?

    lines = expired.map { |c| "- #{c.user&.full_name} never reported on #{c.initiative&.title || 'the metric'}" }
    "Unanswered check-ins (gaps) this period:\n#{lines.join("\n")}"
  end

  # period_start/period_end may be Dates (the end-of-cycle job passes
  # start_date/end_date) or Times (the weekly job passes a summary_time
  # moment) — normalize to a full-day span in the Date case so the window
  # actually covers the whole day rather than being cast to midnight.
  def window
    start = context.period_start.is_a?(Date) ? context.period_start.beginning_of_day : context.period_start
    finish = context.period_end.is_a?(Date) ? context.period_end.end_of_day : context.period_end

    start..finish
  end
end
