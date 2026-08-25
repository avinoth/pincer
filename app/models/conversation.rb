class Conversation < ApplicationRecord
  enum :surface, {
    assistant: "assistant",
    channel: "channel",
    dm: "dm"
  }, prefix: true

  belongs_to :organization

  has_many :conversation_messages, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :agent_runs, dependent: :destroy

  validates :slack_channel_id, :slack_thread_ts, :surface, presence: true

  def latest_run
    agent_runs.order(created_at: :desc).first
  end
end
