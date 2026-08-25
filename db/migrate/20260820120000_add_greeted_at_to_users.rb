class AddGreetedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :greeted_at, :datetime  # first time we showed the capabilities greeting
  end
end
