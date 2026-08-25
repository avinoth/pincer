class CreateMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics do |t|
      # A goal has exactly one primary metric; the unique index enforces it.
      t.references :goal, null: false, foreign_key: true, index: { unique: true }

      t.string :name, null: false
      t.string :unit

      # Decimal so money, percentages, and counts all fit one type.
      # current_value is denormalized from the latest MetricUpdate (seeded to
      # start_value at creation, before any update exists).
      t.decimal :start_value, precision: 15, scale: 4
      t.decimal :current_value, precision: 15, scale: 4
      t.decimal :target_value, precision: 15, scale: 4, null: false

      # increase | decrease — "metric met" is direction-aware.
      t.string :direction, null: false

      t.timestamps
    end
  end
end
