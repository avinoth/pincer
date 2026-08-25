# frozen_string_literal: true

# Canned reply posted (threaded) when the bot is @-mentioned — echoes the user's
# message back and offers a "Wave" button that exercises the interaction router.
class Slack::Messages::MentionReply < Slack::Messages::Base
  # Strips a leading "<@U…>" bot mention token from the event text.
  MENTION_TOKEN = /\A\s*<@[UW][A-Z0-9]+>\s*/

  def initialize(text:)
    @echo = text.to_s.sub(MENTION_TOKEN, "").strip
  end

  def text
    "You said: #{@echo}"
  end

  def blocks
    [
      section(":wave: Thanks for the shout! You said:"),
      section("> #{@echo.presence || '_(nothing)_'}"),
      actions([ button("Wave back 👋", action_id: "wave", value: "wave") ])
    ]
  end
end
