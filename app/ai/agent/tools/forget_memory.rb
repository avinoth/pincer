# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Deactivates a memory (never destroys — Memory#active is the durable
      # record of "we used to believe this"). Visibility mirrors what's actually
      # injected into a prompt: org-scoped memories can be deactivated by
      # anyone in the org, user-scoped ones only by the user they belong to.
      class ForgetMemory < Base
        description "Forget (deactivate) a memory by id. Only forget a memory the user clearly " \
                    "wants gone — check with them first if it's ambiguous which one they mean."

        param :memory_id, type: "integer", desc: "The memory's id, as shown in the Memory sections above."

        def execute(memory_id:)
          memory = visible_memories.find_by(id: memory_id)
          return { error: "No memory with id #{memory_id} is visible to you." } unless memory

          memory.update!(active: false)
          { forgotten: true, memory_id: memory.id }
        rescue StandardError => e
          { error: "Couldn't forget memory #{memory_id}: #{e.message}" }
        end

        private

        def visible_memories
          Memory.where(organization: context.organization).where(user_id: [ nil, context.user.id ])
        end
      end
    end
  end
end
