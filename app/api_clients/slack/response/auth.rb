class Slack::Response::Auth < Slack::Response::Base
  def app_id
    @response[:app_id]
  end

  def bot_id
    @response[:bot_user_id]
  end

  def access_token
    @response[:access_token]
  end

  def refresh_token
    @response[:refresh_token]
  end

  def token_expires_at
    return if @response[:expires_in].blank?

    Time.current + @response[:expires_in].to_i.seconds
  end

  def user_id
    @response.dig(:authed_user, :id)
  end

  def team_id
    @response.dig(:team, :id)
  end

  def team_name
    @response.dig(:team, :name)
  end

  def email_domain
    @response.dig(:team, :email_domain)
  end

  def full_user_info(organization)
    Slack::Request::UserById.new(organization.slack_workspace, user_id).get
  end
end
