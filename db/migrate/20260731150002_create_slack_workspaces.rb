class CreateSlackWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_workspaces do |t|
      # One Slack workspace per organization (unique index on the FK).
      t.references :organization, null: false, foreign_key: true,
        index: { unique: true, name: "workspace_unique_organization_id" }
      t.string :name, null: false
      t.string :identifier, null: false # Slack team_id
      t.string :access_token, null: false
      t.string :refresh_token, null: false
      t.datetime :access_token_expires_at
      t.string :installation_uid
      t.string :bot_uid

      t.timestamps
    end

    add_index :slack_workspaces, :identifier
  end
end
