require "rails_helper"

RSpec.describe "Admin panel SlackWorkspace field masking", type: :request do
  around do |example|
    original = ENV.to_hash.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "s3cret-pw"
    example.run
    original.each { |k, v| ENV[k] = v }
  end

  def basic_auth_header
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret-pw") }
  end

  let!(:workspace) { create(:slack_workspace, access_token: "xoxb-REAL-SECRET-VALUE", refresh_token: "xoxe-REAL-REFRESH-VALUE") }

  describe "GET /admin/slack_workspace/:id (show, HTML)" do
    it "never renders the raw access_token or refresh_token" do
      get "/admin/slack_workspace/#{workspace.id}", headers: basic_auth_header.merge("HTTP_ACCEPT" => "text/html")

      expect(response.body).not_to include(workspace.access_token)
      expect(response.body).not_to include(workspace.refresh_token)
    end
  end

  describe "GET /admin/slack_workspace/:id (show, JSON — RailsAdmin's default format for a bare Accept header)" do
    it "never renders the raw access_token or refresh_token" do
      get "/admin/slack_workspace/#{workspace.id}", headers: basic_auth_header

      expect(response.body).not_to include(workspace.access_token)
      expect(response.body).not_to include(workspace.refresh_token)
    end
  end

  describe "GET /admin/slack_workspace/:id/edit" do
    it "never renders the raw access_token or refresh_token" do
      get "/admin/slack_workspace/#{workspace.id}/edit", headers: basic_auth_header

      expect(response.body).not_to include(workspace.access_token)
      expect(response.body).not_to include(workspace.refresh_token)
    end

    it "has no editable input field for either token" do
      get "/admin/slack_workspace/#{workspace.id}/edit", headers: basic_auth_header

      expect(response.body).not_to include('name="slack_workspace[access_token]"')
      expect(response.body).not_to include('name="slack_workspace[refresh_token]"')
    end
  end

  describe "GET /admin/slack_workspace (index)" do
    it "never renders the raw access_token or refresh_token" do
      get "/admin/slack_workspace", headers: basic_auth_header.merge("HTTP_ACCEPT" => "text/html")

      expect(response.body).not_to include(workspace.access_token)
      expect(response.body).not_to include(workspace.refresh_token)
    end
  end
end
