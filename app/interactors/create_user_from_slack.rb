class CreateUserFromSlack
  include Interactor

  def call
    organization = context.organization

    existing = organization.users.find_by(provider_uid: context.slack_user_id)
    if existing.present?
      context.user = existing
      return
    end

    slack_user = Slack::Request::UserById.new(organization.slack_workspace, context.slack_user_id).get

    unless slack_user.success?
      Bugsnag.notify("User not found in Slack", { slack_user_id: context.slack_user_id, organization_id: organization.id })
      context.fail!(error: :user_fetch_failed)
    end

    context.fail!(error: :bot_user) if slack_user.user.is_bot?

    user = User.create_from_slack(slack_user.user, organization.id, context.user_role || :member)

    unless user.persisted?
      Bugsnag.notify("User creation failed", { slack_user_id: context.slack_user_id, organization_id: organization.id })
      context.fail!(error: :user_create_failed)
    end

    context.user = user

    # Record the installing user as the organization owner.
    # TODO: This is trouble as when later if we're provisioning a user with owner privilige, this will override
    # the organization's owner. Revisit this when introducing user roles.
    organization.update(owner_id: user.id) if user.owner?
    # The installer's tz (already fetched above via users.info for the User
    # record) is the only real timezone proxy Slack exposes — there's no
    # workspace-level timezone API. Applies on both fresh install and
    # re-install (this interactor runs every time via
    # OrganizationSignupFromSlack).
    organization.update(time_zone: user.time_zone) if user.owner?
  end
end
