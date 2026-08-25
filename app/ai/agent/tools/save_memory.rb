# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Persists a durable fact or preference to Organization or User Memory
      # (see Ai::Agent::SystemPrompt, which injects active memories back into
      # future turns' prompts). Org-scoped memories have user_id nil; user-scoped
      # ones belong to the turn's author, never a name the LLM was merely told.
      class SaveMemory < Base
        SCOPES = %w[organization user].freeze

        description "Save a durable fact or preference to memory, so future conversations can " \
                    "use it. Only call this when the user states something worth remembering " \
                    "long-term (not for one-off requests) — and always tell them what you saved."

        param :content, desc: "The fact or preference to remember, written plainly."
        param :scope, desc: "Who this applies to: \"organization\" or \"user\"."
        param :category, required: false, desc: "A short free-text label, e.g. \"preference\" or \"convention\"."

        def execute(content:, scope:, category: nil)
          unless SCOPES.include?(scope)
            return { error: "scope must be one of #{SCOPES.join(', ')}, got #{scope.inspect}" }
          end

          memory = Memory.create!(
            organization: context.organization,
            user: scope == "user" ? context.user : nil,
            content: content,
            category: category,
            source_conversation: context.conversation,
          )

          { saved: true, memory_id: memory.id, scope: scope }
        rescue StandardError => e
          { error: "Couldn't save memory: #{e.message}" }
        end
      end
    end
  end
end
