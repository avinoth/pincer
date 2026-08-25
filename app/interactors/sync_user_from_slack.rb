class SyncUserFromSlack
  include Interactor

  def call
    slack_user = context.slack_user

    if slack_user.is_bot? || slack_user.is_deleted?
      context.user = nil
      return
    end

    context.user = User.sync_from_slack(slack_user, context.organization.id, role: context.user_role || :member)

    return unless context.user.errors.any?

    Bugsnag.notify("User sync failed from Slack") do |report|
      report.add_tab(:context, { organization_id: context.organization.id, errors: context.user.errors.full_messages })
    end
    context.fail!(error: :user_sync_failed)
  end
end
