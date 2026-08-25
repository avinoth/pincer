class ConversationMessage < ApplicationRecord
  enum :role, {
    user: "user",
    assistant: "assistant",
    tool: "tool",
    event: "event"
  }, prefix: true

  belongs_to :conversation
  belongs_to :user, optional: true

  validates :role, presence: true
end
