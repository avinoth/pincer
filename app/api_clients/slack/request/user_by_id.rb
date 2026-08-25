class Slack::Request::UserById < Slack::Request::Base
  def initialize(workspace, slack_id, cache: true)
    super(workspace)
    @slack_id = slack_id
    @cache = cache
  end

  def get
    response = @cache ? cached_request : make_request

    Slack::Response::User.new(response)
  end

  protected

  def make_request
    client.users_info(user: @slack_id)
  rescue => e
    Bugsnag.notify(e, { slack_id: @slack_id, workspace_id: @workspace.id })
    nil
  end

  def cache_key
    "#{@workspace.id}:User:#{@slack_id}"
  end
end
