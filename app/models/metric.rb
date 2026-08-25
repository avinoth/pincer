# A goal's single primary metric — what makes the goal measurable. Created via the
# Create Goal modal or the conversational flow. Values are decimals so
# percentages, money, and counts share one type; `unit` is the free-text label.
# See docs/data_model.md.
class Metric < ApplicationRecord
  # Currency-style units read naturally as a prefix ("$40"); everything else is a
  # suffix — symbolic units glue on ("40%"), word units get a space ("40 signups").
  PREFIX_SYMBOLS = %w[$ £ € ¥ ₹].freeze

  # Whether progress means the value going up or down — "metric met" is
  # direction-aware (e.g. "reduce churn from 8% to 5%").
  enum :direction, {
    increase: "increase",
    decrease: "decrease"
  }, prefix: "direction"

  belongs_to :goal
  has_many :metric_updates, dependent: :destroy

  validates :name, :target_value, :direction, presence: true

  # Formats a value + free-text unit for display, positioning the unit by kind.
  # Stateless so any surface (Slack, web UI, serializers) can reuse it, including
  # for extracted drafts that have a value + unit but no persisted Metric yet.
  # A nil value yields a bare em-dash — a unit on its own ("$—", "—%") is
  # meaningless.
  def self.format_value(value, unit)
    number = format_number(value)
    return "—" if number.nil?
    return number if unit.blank?

    if PREFIX_SYMBOLS.include?(unit)
      "#{unit}#{number}"
    elsif unit.match?(/\A\W+\z/)
      "#{number}#{unit}"
    else
      "#{number} #{unit}"
    end
  end

  # Trims a decimal's trailing ".0", e.g. 20.0 -> "20", 5.5 -> "5.5". Nil-safe:
  # returns nil (not "—") for a blank value, so callers that don't want the
  # em-dash placeholder (e.g. editable-input initial values) can use it directly.
  def self.format_number(value)
    return nil if value.blank?

    decimal = value.to_d
    decimal.frac.zero? ? decimal.to_i.to_s : decimal.to_s("F")
  end

  def formatted_current_value
    self.class.format_value(current_value, unit)
  end

  def formatted_target_value
    self.class.format_value(target_value, unit)
  end

  # Fraction of the distance from start_value to target_value that current_value has covered,
  # direction-aware (increase vs decrease). nil when any value is missing or start == target
  # (no distance to measure progress against). Always clamped to 0.0..1.0.
  def progress_fraction
    return nil if start_value.blank? || current_value.blank? || target_value.blank?
    return nil if target_value == start_value

    numerator, denominator = if direction_decrease?
      [ start_value - current_value, start_value - target_value ]
    else
      [ current_value - start_value, target_value - start_value ]
    end

    (numerator.to_f / denominator.to_f).clamp(0.0, 1.0)
  end

  def progress_percent
    fraction = progress_fraction
    return nil if fraction.nil?

    (fraction * 100).round
  end

  # Formatted delta remaining to reach target_value (e.g. "$71"). nil when the metric has
  # already reached (or passed, direction-aware) its target, or when values are missing.
  def remaining_to_target
    return nil if current_value.blank? || target_value.blank?

    reached = direction_decrease? ? current_value <= target_value : current_value >= target_value
    return nil if reached

    self.class.format_value((target_value - current_value).abs, unit)
  end

  def last_updated_at
    metric_updates.maximum(:created_at)
  end
end
