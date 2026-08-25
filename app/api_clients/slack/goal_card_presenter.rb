# Centralizes the computed display values shared by the goal detail card (GoalDisplay) and the
# goal summary cards (GoalSummaryList), so both render identically off the same goal.
class Slack::GoalCardPresenter
  include Slack::Blocks

  STATUS_COLORS = {
    "not_started" => "#9E9E9E",
    "ended" => "#9E9E9E",
    "completed" => "#2EB67D",
    "in_progress" => "#3AA3E3"
  }.freeze

  HEALTH_COLORS = {
    "on_track" => "#2EB67D",
    "at_risk" => "#E8A33D",
    "off_track" => "#E01E5A"
  }.freeze

  PACE_AHEAD_THRESHOLD = 0.05
  PACE_BEHIND_THRESHOLD = -0.05

  def initialize(goal:)
    @goal = goal
  end

  def status_badge
    goal.publishing_draft? ? "📝 Draft" : Slack::Messages::GoalDisplay::LIFECYCLE_BADGES.fetch(goal.status)
  end

  def status_label
    status_badge.split(" ", 2).last
  end

  # Status sets the base color; health, when present, overrides it.
  def card_color
    HEALTH_COLORS[goal.health] || STATUS_COLORS.fetch(goal.status, STATUS_COLORS["in_progress"])
  end

  def progress_bar
    percent = metric&.progress_percent
    return nil if percent.nil?

    filled = (percent / 10.0).round.clamp(0, 10)
    "#{'▓' * filled}#{'░' * (10 - filled)} #{percent}%"
  end

  # {emoji:, label:} comparing time-elapsed fraction to progress fraction, or nil when there's
  # no metric progress or no date range to measure pace against.
  def pace
    fraction = metric&.progress_fraction
    return nil if fraction.nil?

    elapsed = time_elapsed_fraction
    return nil if elapsed.nil?

    delta = fraction - elapsed
    if delta > PACE_AHEAD_THRESHOLD
      { emoji: "🔥", label: "ahead of pace" }
    elsif delta < PACE_BEHIND_THRESHOLD
      { emoji: "⚠️", label: "behind pace" }
    else
      { emoji: "✅", label: "on pace" }
    end
  end

  def days_left
    return nil if goal.end_date.blank?

    (goal.end_date - Date.current).to_i
  end

  def dates_text
    return nil if goal.start_date.blank? || goal.end_date.blank?

    "#{goal.start_date.strftime('%b %-d')} – #{goal.end_date.strftime('%b %-d, %Y')}"
  end

  # Context-block elements: an image element per owner with an avatar, else a "👤 name" text.
  def owners_avatars
    goal.owners.map do |owner|
      image_url = owner.images&.dig("image_72")
      image_url.present? ? image_element(image_url: image_url, alt_text: owner.full_name) : mrkdwn("👤 #{owner.full_name}")
    end
  end

  def last_updated_text
    updated_at = metric&.last_updated_at
    return nil if updated_at.nil?

    days = ((Date.current - updated_at.to_date).to_i)
    days <= 0 ? "Updated today" : "Updated #{days}d ago"
  end

  def metric
    goal.metric
  end

  private

  attr_reader :goal

  def time_elapsed_fraction
    return nil if goal.start_date.blank? || goal.end_date.blank?

    total_days = (goal.end_date - goal.start_date).to_f
    return nil if total_days <= 0

    elapsed_days = (Date.current - goal.start_date).to_f.clamp(0.0, total_days)
    elapsed_days / total_days
  end
end
