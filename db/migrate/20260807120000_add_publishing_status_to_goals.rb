class AddPublishingStatusToGoals < ActiveRecord::Migration[8.1]
  def up
    add_column :goals, :publishing_status, :string, null: false, default: "published"
    add_index  :goals, :publishing_status
    change_column_default :goals, :status, from: "active", to: "in_progress"
    execute "UPDATE goals SET status = 'in_progress' WHERE status = 'active'"
  end

  def down
    execute "UPDATE goals SET status = 'active' WHERE status = 'in_progress'"
    change_column_default :goals, :status, from: "in_progress", to: "active"
    remove_column :goals, :publishing_status
  end
end
