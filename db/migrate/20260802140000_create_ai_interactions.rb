class CreateAiInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_interactions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      # Raw Slack identity of the turn (user may not be a known User yet).
      t.string :slack_user_id
      t.string :slack_channel_id
      t.string :slack_message_ts
      t.string :slack_thread_ts

      t.text :raw_text
      t.text :cleaned_text

      # Resolved route for the turn + the classifier's confidence.
      t.string :intent
      t.decimal :intent_confidence, precision: 4, scale: 3

      t.string :status, null: false, default: "received"

      # The structured draft this turn produced + what entity it represents.
      t.string :draft_type
      t.jsonb :draft, null: false, default: {}

      t.text :error

      t.timestamps
    end

    add_index :ai_interactions, :status
    add_index :ai_interactions, :intent
  end
end
