class AddAgentRunIdToLlmCalls < ActiveRecord::Migration[8.1]
  def change
    add_reference :llm_calls, :agent_run, null: true, foreign_key: true

    change_column_null :llm_calls, :ai_interaction_id, true
  end
end
