class AddCreatorToInitiatives < ActiveRecord::Migration[8.1]
  def change
    # Who created the initiative — distinct from its owner. Nullable, and
    # nullifies on the creator's User row being deleted, so the initiative
    # itself never gets swept away by a departed user's removal.
    add_reference :initiatives, :creator, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
