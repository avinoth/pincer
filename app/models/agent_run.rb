class AgentRun < ApplicationRecord
  enum :status, {
    running: "running",
    paused_on_tool: "paused_on_tool",
    completed: "completed",
    failed: "failed"
  }, prefix: "status"

  belongs_to :conversation
  has_many :llm_calls, dependent: :nullify

  validates :status, presence: true

  scope :paused_on_tool, -> { where(status: "paused_on_tool") }
end
