# frozen_string_literal: true

# Rich first-ever assistant-thread greeting (once per user). Returning users get
# the plain Slack::Messages::AssistantGreeting instead.
class Slack::Messages::AssistantWelcome < Slack::Messages::Base
  include Slack::Messages::Capabilities

  def initialize(name:)
    @name = name
  end

  def text
    "Hi #{@name}! I'm Pincer — here's what I can help you with."
  end

  def blocks
    [
      section("Hi #{@name} :wave: I'm *Pincer*, your execution partner for the company's goals."),
      divider,
      capability_section,
      context([ mrkdwn("Ready when you are — pick a suggested prompt, or just tell me what you're working on.") ])
    ]
  end
end
