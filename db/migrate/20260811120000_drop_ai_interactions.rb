class DropAiInteractions < ActiveRecord::Migration[8.1]
  def change
    remove_reference :llm_calls, :ai_interaction, foreign_key: true

    drop_table :ai_interactions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.string :slack_user_id
      t.string :slack_channel_id
      t.string :slack_message_ts
      t.string :slack_thread_ts

      t.text :raw_text
      t.text :cleaned_text

      t.string :intent
      t.decimal :intent_confidence, precision: 4, scale: 3

      t.string :status, null: false, default: "received"

      t.string :draft_type
      t.jsonb :draft, null: false, default: {}

      t.text :error

      t.references :produced, polymorphic: true, null: true

      t.timestamps

      t.index :status
      t.index :intent
    end
  end
end
