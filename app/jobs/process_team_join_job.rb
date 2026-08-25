# Async entry point for a Slack `team_join` event. Resolves the org and
# delegates to SyncUserFromSlack so a new workspace member is provisioned in
# our DB without waiting for their first interaction with the bot.
class ProcessTeamJoinJob < ApplicationJob
  queue_as :default

  def perform(team_id:, user:)
    organization = SlackWorkspace.find_by(identifier: team_id)&.organization
    return unless organization

    slack_user = Slack::Type::User.new(user.with_indifferent_access)
    result = SyncUserFromSlack.call(organization: organization, slack_user: slack_user)

    if result.failure?
      Bugsnag.notify("SyncUserFromSlack failed for team_join") do |report|
        report.add_tab(:context, { organization_id: organization.id, error: result.error })
      end
    end
  rescue => e
    Bugsnag.notify(e, { team_id: team_id })
  end
end
