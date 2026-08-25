class CreateOrganizationFromSlack
  include Interactor

  def call
    existing = SlackWorkspace.find_by(identifier: context.slack_response.team_id)&.organization

    if existing.present?
      existing.update_details_from_slack(context.slack_response)
      context.organization = existing
    else
      organization = Organization.create_from_slack(context.slack_response)
      context.organization = organization
      context.user_role = :owner
      context.organization_created = true
    end

    context.slack_user_id = context.slack_response.user_id
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: :organization_create_failed)
  end

  def rollback
    if User.exists?(organization_id: context.organization&.id)
      Bugsnag.notify(
        "Rollback of CreateOrganizationFromSlack: organization already has users. Not destroying.",
        { organization_id: context.organization&.id },
      )
    else
      context.organization&.destroy
    end
  end
end
