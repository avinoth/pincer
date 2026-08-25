# frozen_string_literal: true

# Reference modal demonstrating the Views::Modal base + the view_submission path.
# Its callback_id ("example") is routed to Slack::Interactions::ExampleSubmission.
class Slack::Views::ExampleModal < Slack::Views::Modal
  CALLBACK_ID = "example"

  def callback_id
    CALLBACK_ID
  end

  def title
    "Example"
  end

  def blocks
    [
      section("A reference modal. Type something and submit."),
      input(
        label: "Your note",
        element: plain_text_input(action_id: "note", multiline: true),
        block_id: "note_block",
      )
    ]
  end
end
