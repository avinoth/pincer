class Initiative < ApplicationRecord
  enum :status, {
    proposed: "proposed",
    in_progress: "in_progress",
    done: "done",
    dropped: "dropped"
  }, prefix: "status"

  belongs_to :goal
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :creator, class_name: "User", optional: true

  has_many :checkins, dependent: :destroy
  has_many :goal_updates, dependent: :destroy

  validates :title, :status, presence: true

  # Slack user id (User#provider_uid). The initiative's own owner, or anyone
  # who could modify the parent goal (creator or an owner), may modify it.
  def modifiable_by?(slack_user_id)
    return false if slack_user_id.blank?

    owner&.provider_uid == slack_user_id || goal.modifiable_by?(slack_user_id)
  end
end
