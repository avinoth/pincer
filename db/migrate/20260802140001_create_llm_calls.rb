class CreateLlmCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_calls do |t|
      t.references :ai_interaction, null: false, foreign_key: true
      t.references :organization, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.string :task, null: false
      t.string :model
      t.string :provider

      t.jsonb :request_messages, null: false, default: {}
      t.jsonb :raw_response, null: false, default: {}
      t.jsonb :parsed_output, null: false, default: {}

      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.decimal :cost, precision: 12, scale: 6
      t.integer :latency_ms

      t.string :status, null: false
      t.boolean :repaired, null: false, default: false
      t.decimal :temperature, precision: 3, scale: 2

      t.text :error

      t.timestamps
    end

    add_index :llm_calls, [ :task, :status ]
  end
end
