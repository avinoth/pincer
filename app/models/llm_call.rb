# One structured LLM call within an agent run: what was sent, what came
# back, and the cost/latency/outcome — the per-call observability record.
class LlmCall < ApplicationRecord
  enum :task, {
    agent_turn: "agent_turn"
  }, prefix: true

  enum :status, {
    success: "success",
    failed: "failed"
  }, prefix: "status"

  belongs_to :organization, optional: true
  belongs_to :user, optional: true
  belongs_to :agent_run, optional: true

  validates :task, :status, presence: true
end
