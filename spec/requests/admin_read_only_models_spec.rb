require "rails_helper"

RSpec.describe "Admin panel read-only models", type: :request do
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

  # Agent-generated operational state — see config/initializers/rails_admin.rb.
  # Ad-hoc edits/deletes risk corrupting live agent context, so these models
  # get index/show/search/export only.
  read_only_models = %w[llm_call memory conversation conversation_message agent_run]

  read_only_models.each do |model_name|
    describe "#{model_name} (read-only)" do
      it "renders no New link on the index page" do
        get "/admin/#{model_name}", headers: basic_auth_header

        expect(response.body).not_to include("/admin/#{model_name}/new")
      end

      it "rejects the new action" do
        get "/admin/#{model_name}/new", headers: basic_auth_header

        expect(response).to have_http_status(:forbidden)
      end

      it "rejects a direct POST create" do
        model_class = model_name.classify.constantize

        expect {
          post "/admin/#{model_name}/new", params: {}, headers: basic_auth_header
        }.not_to change { model_class.count }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "an unrestricted model (Metric), for contrast" do
    it "renders a New link on the index page" do
      get "/admin/metric", headers: basic_auth_header

      expect(response.body).to include("/admin/metric/new")
    end

    it "allows the new action" do
      get "/admin/metric/new", headers: basic_auth_header

      expect(response).to have_http_status(:ok)
    end
  end
end
