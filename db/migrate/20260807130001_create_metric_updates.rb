class CreateMetricUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :metric_updates do |t|
      t.references :metric, null: false, foreign_key: true
      # Attributed to the sender, who may differ from the goal owner.
      t.references :reported_by, null: false, foreign_key: { to_table: :users }

      t.decimal :value, precision: 15, scale: 4, null: false
      t.text :note

      t.timestamps
    end
  end
end
