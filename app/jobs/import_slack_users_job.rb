class ImportSlackUsersJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    organization.users_import_in_progress!

    result = ImportUsersFromSlack.call(organization: organization)

    if result.failure?
      organization.users_import_failed!
      Bugsnag.notify("ImportUsersFromSlack failed") do |report|
        report.add_tab(:context, { organization_id: organization.id, error: result.error })
      end
    else
      organization.users_import_completed!
    end
  end
end
