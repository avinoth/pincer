module Slack::Messages::Capabilities
  def capability_section
    section(<<~MRKDWN)
      *Here's what I can help you with:*
      :dart: *Track goals & initiatives* — create, view, and update your goals and initiatives.
      :chart_with_upwards_trend: *Log progress* — report a metric, add a quick note, or complete your weekly check-in.
      :bell: *Stay in the loop* — I'll nudge you for check-ins and post weekly summaries plus goal start/end updates.
      :brain: *Remember what matters* — tell me a fact or preference and I'll hold onto it.
    MRKDWN
  end
end
