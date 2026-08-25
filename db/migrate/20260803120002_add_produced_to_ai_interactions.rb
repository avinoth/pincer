class AddProducedToAiInteractions < ActiveRecord::Migration[8.1]
  def change
    # Polymorphic link to the record this interaction produced (a Goal now;
    # Initiative / MetricUpdate / etc. later). Distinct from draft_type, which
    # tags the pre-creation draft.
    add_column :ai_interactions, :produced_type, :string
    add_column :ai_interactions, :produced_id, :bigint
    add_index :ai_interactions, [ :produced_type, :produced_id ]
  end
end
