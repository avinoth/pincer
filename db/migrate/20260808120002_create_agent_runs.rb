class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.references :conversation, null: false, foreign_key: true

      t.string :status, null: false, default: "running"
      t.jsonb :pending_tool_call
      t.jsonb :error

      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :cost, precision: 12, scale: 6
      t.integer :duration_ms

      t.timestamps
    end

    add_index :agent_runs, [ :conversation_id, :created_at ]
  end
end
