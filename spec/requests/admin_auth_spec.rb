require "rails_helper"

RSpec.describe "Admin panel authentication", type: :request do
  around do |example|
    original = ENV.to_hash.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "s3cret-pw"
    example.run
    original.each { |k, v| ENV[k] = v }
  end

  def basic_auth_header(username, password)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end

  describe "GET /admin" do
    it "returns 401 with no credentials" do
      get "/admin"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with wrong credentials" do
      get "/admin", headers: basic_auth_header("admin", "wrong-pw")

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with correct credentials" do
      get "/admin", headers: basic_auth_header("admin", "s3cret-pw")

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /good_job" do
    it "returns 401 with no credentials" do
      get "/good_job"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with wrong credentials" do
      get "/good_job", headers: basic_auth_header("admin", "wrong-pw")

      expect(response).to have_http_status(:unauthorized)
    end

    it "redirects (successfully authenticated) with correct credentials" do
      get "/good_job", headers: basic_auth_header("admin", "s3cret-pw")

      expect(response).to have_http_status(:found)
    end
  end
end
