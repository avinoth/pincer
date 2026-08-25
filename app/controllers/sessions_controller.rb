class SessionsController < ApplicationController
  before_action :authenticate_user!, only: [ :destroy ]

  # GET /auth/slack/callback — OmniAuth (OpenID Connect) sign-in callback.
  def create
    user_uid = auth_hash&.dig("uid")
    team_id = auth_hash&.dig("extra", "raw_info", "https://slack.com/team_id")

    return redirect_to_frontend(login: "error") if user_uid.blank?

    user = User.find_by(provider_uid: user_uid)

    if user.present?
      return redirect_to_frontend(login: "inactive") unless user.organization.active?

      sign_in(user)
      return redirect_to_frontend(login: "success")
    end

    # Unknown user, but their workspace is already installed → add them.
    organization = SlackWorkspace.find_by(identifier: team_id)&.organization
    return redirect_to_frontend(login: "no_org") if organization.blank?

    result = CreateUserFromSlack.call(
      slack_user_id: user_uid,
      organization: organization,
      user_role: :member,
    )

    if result.success?
      sign_in(result.user)
      redirect_to_frontend(login: "success")
    else
      redirect_to_frontend(login: "error")
    end
  end

  # DELETE /logout
  def destroy
    logout
    head :no_content
  end

  # GET /auth/failure
  def failure
    redirect_to_frontend(login: "error")
  end

  protected

  def auth_hash
    request.env["omniauth.auth"]
  end

  def redirect_to_frontend(query)
    redirect_to(frontend_url(query), allow_other_host: true)
  end
end
