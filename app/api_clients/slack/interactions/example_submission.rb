# frozen_string_literal: true

# view_submission handler for Slack::Views::ExampleModal (callback_id "example").
# Demonstrates reading modal state and returning a `response_action` (validation
# errors here). Returning nil closes the modal.
class Slack::Interactions::ExampleSubmission < Slack::Interactions::Base
  def call
    note = payload.dig(:view, :state, :values, :note_block, :note, :value).to_s

    if note.strip.empty?
      return { response_action: "errors", errors: { note_block: "Please enter a note" } }
    end

    # A real handler would persist / act on `note` here (scoped to #organization).
    nil
  end
end
