class AppHomeDisplayJob < ApplicationJob
  queue_as :default

  # STUB SEAM — App Home UX not yet specified.
  #
  # Contract: perform(slack_user_id, team_id)
  # Intended behavior: build a Block Kit view and publish it via
  #   Slack::Web::Client#views_publish(user_id:, view:) for the given user.
  # Fill this in once the App Home tab content is designed.
  def perform(slack_user_id, team_id)
    Rails.logger.info("[AppHomeDisplayJob] stub: user=#{slack_user_id} team=#{team_id}")
  end
end
