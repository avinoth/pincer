class SendWelcomeMessageJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    owner = organization.owner || organization.users.owner.first
    return unless owner

    # DM the owner (channel = their Slack user id opens a DM for the bot).
    reply = Slack::Messages::Welcome.new(organization: organization, owner: owner)
    Slack::Request::SendMessage.new(organization.slack_workspace)
      .send_message(owner.provider_uid, reply.to_h)
    owner.update!(greeted_at: Time.current)
  rescue => e
    Bugsnag.notify(e, { organization_id: organization_id })
  end
end
