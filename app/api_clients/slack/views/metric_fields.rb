# frozen_string_literal: true

# Shared metric block builders for the Create Goal modal's inline metric
# section (CreateGoalModal) and the Edit Goal modal's inline metric section
# (EditGoalModal). `source` may be either an extracted draft Hash (any subset of
# name/start_value/target_value/direction/unit) or a persisted Metric.
#
# Once any MetricUpdate exists on a metric it's frozen — Slack has no way to grey
# out an input block — so callers render #metric_readonly_blocks (plain text)
# instead of #metric_input_blocks for that goal.
module Slack::Views::MetricFields
  DIRECTIONS = { "increase" => "Increase", "decrease" => "Decrease" }.freeze

  private

  def metric_input_blocks(source)
    values = metric_values(source)

    [
      input(
        label: "What to track",
        block_id: "name_block",
        element: plain_text_input(
          action_id: "name",
          placeholder: "e.g. Activation rate",
          initial_value: values[:name],
        ),
      ),
      input(
        label: "Direction",
        block_id: "direction_block",
        element: static_select(
          action_id: "direction",
          placeholder: "Increase or decrease",
          options: direction_options,
          initial_option: direction_initial_option(values[:direction]),
        ),
      ),
      input(
        label: "Start value",
        block_id: "start_value_block",
        optional: true,
        hint: "The baseline today. Defaults to 0 if left blank.",
        element: number_input(action_id: "start_value", initial_value: values[:start_value]),
      ),
      input(
        label: "Target value",
        block_id: "target_value_block",
        element: number_input(action_id: "target_value", initial_value: values[:target_value]),
      ),
      input(
        label: "Unit",
        block_id: "unit_block",
        optional: true,
        element: plain_text_input(
          action_id: "unit",
          placeholder: "e.g. %, $, signups",
          initial_value: values[:unit],
        ),
      )
    ]
  end

  def metric_readonly_blocks(metric)
    values = metric_values(metric)

    [
      section(fields: [
        "*What's tracked*\n#{values[:name]}",
        "*Direction*\n#{DIRECTIONS.fetch(values[:direction], values[:direction])}",
        "*Start value*\n#{Metric.format_value(values[:start_value] || "0", values[:unit])}",
        "*Target value*\n#{Metric.format_value(values[:target_value], values[:unit])}"
      ]),
      context([ mrkdwn("Locked — an update has already been reported against this metric.") ])
    ]
  end

  # Normalizes either source into a plain Hash with symbol keys, formatting the
  # numeric fields as clean decimal strings (BigDecimal#to_s defaults to
  # scientific notation, e.g. "0.2e2" for 20 — not something Slack or a human
  # should see).
  def metric_values(source)
    attrs =
      if source.is_a?(Hash)
        source.with_indifferent_access
      else
        {
          name: source&.name,
          direction: source&.direction,
          start_value: source&.start_value,
          target_value: source&.target_value,
          unit: source&.unit
        }
      end

    {
      name: attrs[:name].presence,
      direction: attrs[:direction].presence,
      start_value: numeric_string(attrs[:start_value]),
      target_value: numeric_string(attrs[:target_value]),
      unit: attrs[:unit].presence
    }
  end

  def numeric_string(value)
    Metric.format_number(value)
  end

  def direction_options
    DIRECTIONS.map { |value, label| option(label, value) }
  end

  def direction_initial_option(value)
    return nil unless DIRECTIONS.key?(value)

    option(DIRECTIONS[value], value)
  end
end
