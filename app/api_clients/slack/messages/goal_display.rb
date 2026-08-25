class Slack::Messages::GoalDisplay < Slack::Messages::Base
  PUBLISH_ACTION_ID = "publish_goal"
  EDIT_ACTION_ID = "edit_goal"

  LIFECYCLE_BADGES = {
    "not_started" => "⚪ Not started",
    "in_progress" => "🟢 In progress",
    "completed" => "✅ Completed",
    "ended" => "🏁 Ended"
  }.freeze

  HEALTH_BADGES = {
    "on_track" => "🟢 On track",
    "at_risk" => "🟡 At risk",
    "off_track" => "🔴 Off track"
  }.freeze

  INITIATIVE_STATUS_EMOJIS = {
    "proposed" => "📋",
    "in_progress" => "🚧",
    "done" => "✅",
    "dropped" => "🗑️"
  }.freeze

  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  def initialize(goal:)
    @goal = goal
    @presenter = Slack::GoalCardPresenter.new(goal: goal)
  end

  def text
    "#{status_label}: #{@goal.title}"
  end

  def color
    @presenter.card_color
  end

  def blocks
    [
      header_section,
      description_section,
      metric_section,
      pace_section,
      divider,
      initiatives_section,
      details_context,
      updated_context,
      actions(action_buttons)
    ].compact
  end

  private

  def status_badge
    @goal.publishing_draft? ? "📝 Draft" : LIFECYCLE_BADGES.fetch(@goal.status)
  end

  def status_label
    status_badge.split(" ", 2).last
  end

  def health_badge
    HEALTH_BADGES[@goal.health]
  end

  def header_section
    badge_line = [ status_badge, health_badge ].compact.join("  ·  ")
    section("*#{@goal.title}*\n#{badge_line}")
  end

  def description_section
    section(@goal.description) if @goal.description.present?
  end

  def metric_section
    metric = @goal.metric
    return nil if metric.nil?

    lines = [ metric_line(metric) ]
    lines << "`#{@presenter.progress_bar}`" if @presenter.progress_bar
    remaining = metric.remaining_to_target
    lines << "_#{remaining} to go_" if remaining

    section("*Metric*\n#{lines.join("\n")}")
  end

  def metric_line(metric)
    arrow = metric.direction_decrease? ? "↘︎" : "↗︎"
    "#{metric.name}: #{metric.formatted_current_value} → #{metric.formatted_target_value} #{arrow}"
  end

  def pace_section
    pace = @presenter.pace
    days_left = @presenter.days_left
    return nil if pace.nil? && days_left.nil?

    parts = []
    parts << "#{pace[:emoji]} #{pace[:label]}" if pace
    parts << "#{days_left} day#{'s' unless days_left == 1} left" if days_left

    context([ mrkdwn(parts.join("  ·  ")) ])
  end

  def initiatives_section
    return nil if @goal.initiatives.empty?

    lines = @goal.initiatives.map do |initiative|
      emoji = INITIATIVE_STATUS_EMOJIS.fetch(initiative.status, "•")
      owner = initiative.owner&.full_name || "unassigned"
      "#{emoji} #{initiative.title} — _#{owner}_"
    end

    section("*Initiatives*\n#{lines.join("\n")}")
  end

  def details_context
    elements = []
    elements.concat(@presenter.owners_avatars)
    elements << mrkdwn(@presenter.dates_text) if @presenter.dates_text
    elements << mrkdwn("Parent: #{@goal.parent.title}") if @goal.parent
    elements << mrkdwn(updates_text) if @goal.update_channel.present?

    return nil if elements.empty?

    context(elements)
  end

  def updates_text
    return "<##{@goal.update_channel}>" unless @goal.summary_day && @goal.summary_time

    "<##{@goal.update_channel}> · #{DAY_NAMES[@goal.summary_day]} #{@goal.summary_time}"
  end

  def updated_context
    text = @presenter.last_updated_text
    return nil if text.nil?

    context([ mrkdwn("_#{text}_") ])
  end

  def action_buttons
    buttons = []
    buttons << button("Publish goal", action_id: PUBLISH_ACTION_ID, value: @goal.id.to_s, style: "primary") if @goal.publishing_draft?
    buttons << button("Edit goal", action_id: EDIT_ACTION_ID, value: @goal.id.to_s)
    buttons
  end
end
