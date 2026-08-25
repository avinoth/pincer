class CreateSlackInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_interactions do |t|
      # Nullable: url_verification and pre-install traffic have no workspace yet.
      t.references :organization, null: true, foreign_key: true

      t.string :direction, null: false # "inbound" | "outbound"
      t.string :event_type             # app_mention / block_actions / chat.postMessage / ...

      t.string :team_id
      t.string :channel_id
      t.string :slack_user_id
      t.string :ts
      t.string :thread_ts

      # Full raw Slack payload (inbound) or request (outbound); response holds the
      # outbound API result, including the message ts we can later update/react to.
      t.jsonb :payload, null: false, default: {}
      t.jsonb :response

      t.boolean :ok # outbound success flag; null for inbound
      t.text :error

      t.integer :retry_num    # X-Slack-Retry-Num
      t.string :retry_reason  # X-Slack-Retry-Reason

      t.timestamps
    end

    add_index :slack_interactions, :direction
    add_index :slack_interactions, :event_type
    add_index :slack_interactions, :team_id
    add_index :slack_interactions, [ :channel_id, :ts ]
    add_index :slack_interactions, :thread_ts
    add_index :slack_interactions, :created_at
  end
end
