# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Applies a direct edit to one initiative's title, description, owner,
      # or status. Mutates immediately, no confirmation pause: the refreshed
      # InitiativeDisplay card, posted fresh into the thread, carries the Edit
      # button as the built-in override/undo affordance (unlike
      # show_initiative_create_form, this never returns PENDING).
      #
      # Scoped to the current organization (via the parent goal) — an
      # initiative_id from another org is treated as not found. Gated on
      # Initiative#modifiable_by? — only the initiative's owner or the parent
      # goal's creator/owners may edit it. The parent goal itself can't be
      # reassigned here.
      class EditInitiative < Base
        # Slack user mention as it appears in message text, e.g.
        # "<@U012AB>" or the bare "U012AB" — captures the id.
        USER_MENTION_PATTERN = /\A<@([UW][A-Z0-9]+)>\z/
        USER_ID_PATTERN = /\A[UW][A-Z0-9]+\z/

        description "Apply a direct edit to one initiative's title, description, owner, or " \
                    "status. Mutates immediately — no confirmation step. Requires a concrete " \
                    "initiative_id (use pick_initiative to resolve one first, if the user's " \
                    "reference is ambiguous). The parent goal can't be changed here — an " \
                    "initiative always stays under the goal it was created on."

        param :initiative_id, type: "integer", desc: "The initiative's id, as returned by pick_initiative or create_initiative."
        param :title, required: false, desc: "New title."
        param :description, required: false, desc: "New description."
        param :owner, required: false, desc: "New owner's Slack user id, taken from a <@...> mention."
        param :status, required: false, desc: "New status: proposed, in_progress, done, or dropped."

        def execute(initiative_id:, title: nil, description: nil, owner: nil, status: nil)
          initiative = organization_initiatives.find_by(id: initiative_id)
          return { error: "No initiative found with id #{initiative_id}." } unless initiative
          unless initiative.modifiable_by?(context.user&.provider_uid)
            return { error: "Only the initiative's owner or the goal's owners/creator can edit it." }
          end

          owner_user = nil
          if owner.present?
            owner_user = resolve_owner(owner)
            unless owner_user
              return { error: "\"#{owner}\" doesn't look like a user — ask them to be @mentioned so Slack gives me their id." }
            end
          end

          attributes = {
            title: title,
            description: description,
            owner: owner_user,
            status: status
          }.compact

          result = UpdateInitiative.call(initiative: initiative, attributes: attributes)
          return { error: result.error } if result.failure?

          post_initiative_display(result.initiative)
          success_result(result.initiative, attributes.keys)
        rescue StandardError => e
          { error: "Couldn't edit initiative #{initiative_id}: #{e.message}" }
        end

        private

        # Org-scoped via the parent goal — an initiative_id from another org is
        # treated as not found rather than leaking across organizations.
        def organization_initiatives
          Initiative.joins(:goal).where(goals: { organization_id: context.organization.id })
        end

        def resolve_owner(value)
          slack_user_id = normalize_user(value)
          return nil unless slack_user_id

          result = CreateUserFromSlack.call(organization: context.organization, slack_user_id: slack_user_id)
          result.success? ? result.user : nil
        end

        def normalize_user(value)
          match = USER_MENTION_PATTERN.match(value)
          candidate = match ? match[1] : value
          candidate if USER_ID_PATTERN.match?(candidate)
        end

        def post_initiative_display(initiative)
          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            Slack::Messages::InitiativeDisplay.new(initiative: initiative).to_h
              .merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end

        def success_result(initiative, changed_fields)
          {
            id: initiative.id,
            title: initiative.title,
            changed_fields: changed_fields,
            owner: initiative.owner&.full_name,
            status: initiative.status
          }
        end
      end
    end
  end
end
