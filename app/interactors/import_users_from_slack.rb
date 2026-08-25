class ImportUsersFromSlack
  include Interactor

  def call
    response = Slack::Request::UserList.new(context.organization.slack_workspace, cursor: context.cursor).get

    if response.nil? || response.error?
      Bugsnag.notify("Slack user list request failed") do |report|
        report.add_tab(:context, { organization_id: context.organization.id, response: response.inspect })
      end
      context.fail!(error: :users_list_failed)
    end

    slack_members(response).each { |slack_user| import_user(slack_user) }

    if response.next_cursor.present?
      context.cursor = response.next_cursor
      ImportUsersFromSlack.call(context)
    end
  end

  private

  def import_user(slack_user)
    user = User.sync_from_slack(slack_user, context.organization.id, role: :member)

    if user.errors.any?
      Bugsnag.notify("User creation failed while importing from Slack") do |report|
        report.add_tab(:context, { organization_id: context.organization.id, errors: user.errors.full_messages })
      end
    end

    user
  end

  def slack_members(response)
    response.members.reject { |member| member.is_bot? || member.is_deleted? }
  end
end
