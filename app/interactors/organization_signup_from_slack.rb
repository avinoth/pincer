class OrganizationSignupFromSlack
  include Interactor::Organizer

  # Onboarding side-effects run once, only when the organization is first
  # created. Re-installs of an existing workspace re-enter this flow but only
  # update org details, so they must not re-import users or re-send the welcome
  # DM (SendWelcomeMessageJob is not idempotent).
  after do
    next unless context.organization_created

    ImportSlackUsersJob.perform_later(context.organization.id)
    SendWelcomeMessageJob.perform_later(context.organization.id)
  end

  organize PerformSlackOauth, CreateOrganizationFromSlack, CreateUserFromSlack
end
