class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :organization, null: false, foreign_key: true

      t.string :slack_channel_id, null: false
      t.string :slack_thread_ts, null: false
      t.string :surface, null: false

      t.string :title
      t.string :context_hint

      t.timestamps
    end

    add_index :conversations, [ :organization_id, :slack_channel_id, :slack_thread_ts ],
      unique: true, name: "index_conversations_on_org_channel_thread"
  end
end
