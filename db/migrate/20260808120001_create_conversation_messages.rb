class CreateConversationMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.string :role, null: false
      t.text :content
      t.jsonb :tool_calls
      t.string :tool_call_id
      t.string :slack_ts

      t.timestamps
    end

    add_index :conversation_messages, [ :conversation_id, :created_at ]
  end
end
