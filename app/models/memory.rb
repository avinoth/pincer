class Memory < ApplicationRecord
  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :source_conversation, class_name: "Conversation", optional: true

  validates :content, presence: true

  scope :org_scoped, -> { where(user_id: nil) }
  scope :for_user, ->(user) { where(user: user) }
  scope :active, -> { where(active: true) }
end
