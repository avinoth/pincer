# frozen_string_literal: true

# Friendly fallback when the agent turn fails (e.g. the model couldn't produce
# a usable response). Keeps the failure user-facing-graceful; the details are
# on the LlmCall/AgentRun rows and in Bugsnag.
class Slack::Messages::PipelineError < Slack::Messages::Base
  def text
    "Sorry — I couldn't make sense of that. Mind rephrasing?"
  end

  def blocks
    [ section(":warning: Sorry — I couldn't make sense of that. Mind rephrasing?") ]
  end
end
