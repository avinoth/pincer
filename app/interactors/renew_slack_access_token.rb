class RenewSlackAccessToken
  include Interactor

  def call
    response = Slack::Request::TokenAuth.new(context.workspace.refresh_token).refresh

    if response.nil? || !response.success?
      Bugsnag.notify("Slack token refresh failed", { workspace_id: context.workspace.id })
      context.fail!(error: :renewal_failed)
    end

    context.workspace.update_details_from_slack!(response)
  end
end
