# frozen_string_literal: true

# Posted once by AssistantThreadStartedJob when a user opens a fresh Slack Agent
# split-view thread — before they've typed anything. Plain text (no blocks): this
# is a short, personal opener, not a card.
class Slack::Messages::AssistantGreeting < Slack::Messages::Base
  def initialize(name:)
    @name = name
  end

  def text
    "Hello #{@name}! I'm Pincer — what can I do for you today?"
  end
end
