# Join between a Goal and its owner Users (a goal can have multiple owners).
class GoalOwner < ApplicationRecord
  belongs_to :goal
  belongs_to :user

  validates :user_id, uniqueness: { scope: :goal_id }
end
