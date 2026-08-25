# frozen_string_literal: true

# Base for modal views (views.open / views.update). Subclasses provide #title,
# #blocks, a #callback_id (routed by Slack::Interactions::Router on submit), and
# optional #submit_label / #close_label / #private_metadata.
class Slack::Views::Modal < Slack::Views::Base
  def type
    "modal"
  end

  def callback_id
    nil
  end

  def title
    raise NotImplementedError, "#{self.class} must implement #title"
  end

  def submit_label
    "Submit"
  end

  def close_label
    "Cancel"
  end

  def private_metadata
    nil
  end

  # Stable handle for views.update when we won't have the view_id (e.g. a view
  # pushed via a view_submission response_action). Nil for most modals.
  def external_id
    nil
  end

  def to_h
    {
      type: type,
      callback_id: callback_id,
      title: plain_text(title),
      submit: submit_label && plain_text(submit_label),
      close: close_label && plain_text(close_label),
      private_metadata: private_metadata,
      external_id: external_id,
      blocks: blocks
    }.compact
  end
end
