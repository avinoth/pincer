# frozen_string_literal: true

# Composable Block Kit builders. Each method returns a plain hash matching Slack's
# Block Kit schema (https://api.slack.com/reference/block-kit). Pure functions — no
# state — so they're trivially testable and cheap to compose.
#
# Usable two ways:
#   Slack::Blocks.section("hi")                 # module method
#   include Slack::Blocks; section("hi")        # mixed into surface objects
module Slack::Blocks
  module_function

  # --- Text objects ---

  def plain_text(text, emoji: true)
    { type: "plain_text", text: text.to_s, emoji: emoji }
  end

  def mrkdwn(text)
    { type: "mrkdwn", text: text.to_s }
  end

  # --- Layout blocks ---

  def header(text, block_id: nil)
    compact({ type: "header", text: plain_text(text), block_id: block_id })
  end

  # `text` may be a String (rendered as mrkdwn) or a text-object hash.
  def section(text = nil, fields: nil, accessory: nil, block_id: nil)
    compact({
      type: "section",
      text: text && (text.is_a?(Hash) ? text : mrkdwn(text)),
      fields: fields&.map { |f| f.is_a?(Hash) ? f : mrkdwn(f) },
      accessory: accessory,
      block_id: block_id
    })
  end

  def divider(block_id: nil)
    compact({ type: "divider", block_id: block_id })
  end

  def context(elements, block_id: nil)
    compact({ type: "context", elements: Array(elements), block_id: block_id })
  end

  def actions(elements, block_id: nil)
    compact({ type: "actions", elements: Array(elements), block_id: block_id })
  end

  def image(image_url:, alt_text:, title: nil, block_id: nil)
    compact({
      type: "image",
      image_url: image_url,
      alt_text: alt_text,
      title: title && plain_text(title),
      block_id: block_id
    })
  end

  # The element form of an image, for use inside a context block (as opposed to #image, which
  # is a top-level block).
  def image_element(image_url:, alt_text:)
    { type: "image", image_url: image_url, alt_text: alt_text }
  end

  def input(label:, element:, block_id: nil, hint: nil, optional: false)
    compact({
      type: "input",
      label: plain_text(label),
      element: element,
      hint: hint && plain_text(hint),
      optional: optional,
      block_id: block_id
    })
  end

  # --- Elements ---

  def button(text, action_id:, value: nil, style: nil, url: nil, confirm: nil)
    compact({
      type: "button",
      text: plain_text(text),
      action_id: action_id,
      value: value,
      style: style, # "primary" | "danger" | nil
      url: url,
      confirm: confirm
    })
  end

  def option(text, value)
    { text: plain_text(text), value: value.to_s }
  end

  def static_select(action_id:, placeholder:, options:, initial_option: nil)
    compact({
      type: "static_select",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      options: options,
      initial_option: initial_option
    })
  end

  def external_select(action_id:, placeholder:, min_query_length: 1, initial_option: nil)
    compact({
      type: "external_select",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      min_query_length: min_query_length,
      initial_option: initial_option
    })
  end

  def users_select(action_id:, placeholder:, initial_user: nil)
    compact({
      type: "users_select",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      initial_user: initial_user
    })
  end

  def multi_users_select(action_id:, placeholder:, initial_users: nil)
    compact({
      type: "multi_users_select",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      initial_users: initial_users.presence
    })
  end

  # `include` filters conversation types, e.g. %w[public private].
  def conversations_select(action_id:, placeholder:, initial_conversation: nil, include: nil)
    compact({
      type: "conversations_select",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      initial_conversation: initial_conversation,
      filter: include.presence && { include: include }
    })
  end

  def overflow(action_id:, options:)
    { type: "overflow", action_id: action_id, options: options }
  end

  def checkboxes(action_id:, options:, initial_options: nil)
    compact({
      type: "checkboxes",
      action_id: action_id,
      options: options,
      initial_options: initial_options.presence
    })
  end

  def datepicker(action_id:, placeholder:, initial_date: nil)
    compact({
      type: "datepicker",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      initial_date: initial_date
    })
  end

  def timepicker(action_id:, placeholder:, initial_time: nil)
    compact({
      type: "timepicker",
      action_id: action_id,
      placeholder: plain_text(placeholder),
      initial_time: initial_time
    })
  end

  def plain_text_input(action_id:, multiline: false, placeholder: nil, initial_value: nil, max_length: nil)
    compact({
      type: "plain_text_input",
      action_id: action_id,
      multiline: multiline,
      placeholder: placeholder && plain_text(placeholder),
      initial_value: initial_value,
      max_length: max_length
    })
  end

  # Numeric input. `is_decimal` allows fractional values — Slack's schema names
  # this required field `is_decimal_allowed`. `initial_value` / `min_value` must
  # be strings per Slack's schema, so we coerce.
  def number_input(action_id:, is_decimal: true, placeholder: nil, initial_value: nil, min_value: nil)
    compact({
      type: "number_input",
      action_id: action_id,
      is_decimal_allowed: is_decimal,
      placeholder: placeholder && plain_text(placeholder),
      initial_value: initial_value.nil? ? nil : initial_value.to_s,
      min_value: min_value.nil? ? nil : min_value.to_s
    })
  end

  # Drop nil values so payloads stay minimal and Slack-valid.
  def compact(hash)
    hash.compact
  end
end
