require "rails_helper"

RSpec.describe AdminAuth do
  around do |example|
    original = ENV.to_hash.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    example.run
    original.each { |k, v| ENV[k] = v }
  end

  describe ".valid?" do
    context "with ADMIN_USERNAME/ADMIN_PASSWORD set" do
      before do
        ENV["ADMIN_USERNAME"] = "admin"
        ENV["ADMIN_PASSWORD"] = "s3cret-pw"
      end

      it "returns true for matching credentials" do
        expect(AdminAuth.valid?("admin", "s3cret-pw")).to be true
      end

      it "returns false for a wrong password" do
        expect(AdminAuth.valid?("admin", "wrong")).to be false
      end

      it "returns false for a wrong username" do
        expect(AdminAuth.valid?("someone-else", "s3cret-pw")).to be false
      end

      it "returns false for blank credentials" do
        expect(AdminAuth.valid?("", "")).to be false
        expect(AdminAuth.valid?(nil, nil)).to be false
      end
    end

    context "with ADMIN_USERNAME or ADMIN_PASSWORD unset (fails closed)" do
      it "returns false when both are blank, even for a plausible-looking guess" do
        ENV["ADMIN_USERNAME"] = nil
        ENV["ADMIN_PASSWORD"] = nil

        expect(AdminAuth.valid?("admin", "admin")).to be false
      end

      it "returns false when only ADMIN_PASSWORD is set" do
        ENV["ADMIN_USERNAME"] = nil
        ENV["ADMIN_PASSWORD"] = "s3cret-pw"

        expect(AdminAuth.valid?("admin", "s3cret-pw")).to be false
      end

      it "returns false when only ADMIN_USERNAME is set" do
        ENV["ADMIN_USERNAME"] = "admin"
        ENV["ADMIN_PASSWORD"] = nil

        expect(AdminAuth.valid?("admin", "s3cret-pw")).to be false
      end
    end
  end

  describe ".valid_authorization_header?" do
    before do
      ENV["ADMIN_USERNAME"] = "admin"
      ENV["ADMIN_PASSWORD"] = "s3cret-pw"
    end

    it "returns true for a correctly-encoded valid Basic header" do
      header = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret-pw")

      expect(AdminAuth.valid_authorization_header?(header)).to be true
    end

    it "returns false for a correctly-encoded wrong-credential Basic header" do
      header = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong-pw")

      expect(AdminAuth.valid_authorization_header?(header)).to be false
    end

    it "returns false for a non-Basic scheme" do
      header = "Bearer sometoken"

      expect(AdminAuth.valid_authorization_header?(header)).to be false
    end

    it "returns false for malformed base64" do
      header = "Basic %%%not-base64%%%"

      expect(AdminAuth.valid_authorization_header?(header)).to be false
    end

    it "returns false for a blank header" do
      expect(AdminAuth.valid_authorization_header?(nil)).to be false
      expect(AdminAuth.valid_authorization_header?("")).to be false
    end
  end
end
