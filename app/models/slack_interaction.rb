# Append-only log of every interaction between users and our Slack bot, in both
# directions: one row per inbound HTTP payload hitting /slack/* and one per
# conversational outbound Slack Web API call. Sits *beneath* the semantic agent
# turn (AgentRun/LlmCall) — see docs/architecture.md ("Everything is logged").
#
# Every row carries message identity (channel_id + ts + thread_ts), so this log
# doubles as the substrate for later updating/reacting-to/threading messages, not
# just debugging. See TODO.md for the (currently unbounded) retention decision.
class SlackInteraction < ApplicationRecord
  enum :direction, { inbound: "inbound", outbound: "outbound" }

  belongs_to :organization, optional: true

  validates :direction, presence: true

  # Everything we know about one channel thread, oldest first — the natural unit
  # when reconstructing or acting on a conversation.
  scope :in_thread, ->(channel_id, thread_ts) do
    where(channel_id: channel_id, thread_ts: thread_ts).order(:created_at)
  end
end
