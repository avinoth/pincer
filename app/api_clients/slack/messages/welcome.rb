# frozen_string_literal: true

# Welcome DM sent to the installing owner after signup.
class Slack::Messages::Welcome < Slack::Messages::Base
  include Slack::Messages::Capabilities

  def initialize(organization:, owner:)
    @organization = organization
    @owner = owner
  end

  def text
    "Welcome to Pincer, #{@owner.full_name}! #{@organization.name} is all set up."
  end

  def blocks
    [
      header("Welcome to Pincer 🎉"),
      section("Hi #{@owner.full_name} :wave:\n*#{@organization.name}* is all set up — I'm importing your team now."),
      divider,
      capability_section,
      context([ mrkdwn("Just message me right here to get started — try *\"Create a goal for the upcoming quarter\"*") ])
    ]
  end
end
