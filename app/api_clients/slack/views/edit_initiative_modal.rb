# frozen_string_literal: true

# Edit an existing Initiative. Prefilled from the initiative itself. The
# parent goal is shown read-only (context line, not an input) — an initiative
# always stays under the goal it was created on. private_metadata is a JSON
# blob — { initiative_id, channel?, message_ts?, thread_ts? } — carrying both
# the initiative id and the origin card's coordinates (when opened from one),
# so EditInitiativeSubmission can refresh the right message on submit. See
# Slack::Interactions::OpenEditInitiativeModal / EditInitiativeSubmission.
class Slack::Views::EditInitiativeModal < Slack::Views::Modal
  CALLBACK_ID = "edit_initiative"

  STATUS_OPTIONS = %w[proposed in_progress done dropped].freeze

  # @param origin [Hash, nil] the opening context's coordinates — { channel:, message_ts:, thread_ts: }.
  def initialize(initiative:, origin: nil)
    @initiative = initiative
    @origin = origin
  end

  def callback_id
    CALLBACK_ID
  end

  def title
    "Edit Initiative"
  end

  def submit_label
    "Update initiative"
  end

  def private_metadata
    {
      initiative_id: @initiative.id,
      channel: @origin&.dig(:channel),
      message_ts: @origin&.dig(:message_ts),
      thread_ts: @origin&.dig(:thread_ts)
    }.compact.to_json
  end

  def blocks
    [
      section("*Goal:* #{@initiative.goal.title}"),
      input(
        label: "Title",
        block_id: "title_block",
        element: plain_text_input(action_id: "title", initial_value: @initiative.title, max_length: 255),
      ),
      input(
        label: "Description",
        block_id: "description_block",
        optional: true,
        element: plain_text_input(
          action_id: "description",
          multiline: true,
          initial_value: @initiative.description.presence,
          max_length: 2000,
        ),
      ),
      input(
        label: "Owner",
        block_id: "owner_block",
        optional: true,
        element: users_select(
          action_id: "owner",
          placeholder: "Select an owner",
          initial_user: @initiative.owner&.provider_uid,
        ),
      ),
      input(
        label: "Status",
        block_id: "status_block",
        element: static_select(
          action_id: "status",
          placeholder: "Select a status",
          options: status_options,
          initial_option: status_option(@initiative.status),
        ),
      )
    ]
  end

  private

  def status_options
    STATUS_OPTIONS.map { |status| status_option(status) }
  end

  def status_option(status)
    option(status.humanize, status)
  end
end
