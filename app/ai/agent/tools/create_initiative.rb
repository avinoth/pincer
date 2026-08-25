# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Creates an initiative directly, no confirmation pause — the deliberate
      # divergence from the goal-create flow (see show_initiative_create_form,
      # which is the fallback when the model can't confidently determine
      # goal/owner/title on its own). Mutates immediately and posts a fresh
      # InitiativeDisplay card into the thread.
      #
      # Scoped to the current organization — a goal_id from another org is
      # treated as not found. Refuses to attach to a goal in a terminal
      # lifecycle state (completed/ended) — see Goal#accepts_initiatives?.
      # Owner defaults to the requesting user when omitted; the model can
      # supply an explicit owner via a Slack <@U...> mention.
      class CreateInitiative < Base
        # Slack user mention as it appears in message text, e.g.
        # "<@U012AB>" or the bare "U012AB" — captures the id.
        USER_MENTION_PATTERN = /\A<@([UW][A-Z0-9]+)>\z/
        USER_ID_PATTERN = /\A[UW][A-Z0-9]+\z/

        description "Create an initiative directly under a goal — no confirmation step, mutates " \
                    "immediately. Only call this when you can confidently determine all three " \
                    "required fields: a concrete goal_id (use pick_goal first if the reference is " \
                    "ambiguous), a title, and a single owner (from a <@...> mention; if the user " \
                    "didn't name one, it defaults to them). If any of those is missing or " \
                    "ambiguous, call show_initiative_create_form instead. Never tell the user the " \
                    "initiative exists until a tool result confirms it."

        param :goal_id, type: "integer", desc: "The parent goal's id, as returned by list_goals, get_goal, or pick_goal."
        param :title, desc: "The initiative's title."
        param :description, required: false, desc: "Longer description, if given."
        param :owner, required: false,
              desc: "Owner's Slack user id, taken from their <@...> mention. Defaults to the " \
                    "requesting user when omitted."

        def execute(goal_id:, title:, description: nil, owner: nil)
          goal = context.organization.goals.find_by(id: goal_id)
          return { error: "No goal found with id #{goal_id}." } unless goal
          unless goal.accepts_initiatives?
            return { error: "#{goal.title} is #{goal.status.humanize.downcase} and can't take new initiatives." }
          end

          owner_user = resolve_owner(owner)

          # Fully qualified: this tool class shares its name with the top-level
          # ::CreateInitiative interactor, and Ruby's lexical constant lookup
          # would otherwise resolve the bare constant back to this class.
          result = ::CreateInitiative.call(
            goal: goal, creator: context.user, owner: owner_user, title: title, description: description,
          )
          return { error: result.error } if result.failure?

          post_initiative_display(result.initiative)
          success_result(result.initiative)
        rescue StandardError => e
          { error: "Couldn't create the initiative: #{e.message}" }
        end

        private

        # Resolves an explicit owner mention via CreateUserFromSlack (provisioning
        # the User row if this is the first time we've seen them), falling back to
        # the requesting user when no owner was given.
        def resolve_owner(owner)
          slack_user_id = owner.present? ? normalize_user(owner) : context.user&.provider_uid
          return nil if slack_user_id.blank?

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

        def success_result(initiative)
          {
            id: initiative.id,
            title: initiative.title,
            goal_id: initiative.goal_id,
            owner: initiative.owner&.full_name,
            status: initiative.status
          }
        end
      end
    end
  end
end
