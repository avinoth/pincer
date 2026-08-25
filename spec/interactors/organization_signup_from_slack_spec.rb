require "rails_helper"

RSpec.describe OrganizationSignupFromSlack do
  before do
    allow(Slack::Request::Auth).to receive(:new)
      .and_return(instance_double(Slack::Request::Auth, perform_oauth: slack_auth_response))
    allow(Slack::Request::UserById).to receive(:new)
      .and_return(instance_double(Slack::Request::UserById, get: slack_user_response))
  end

  it "creates the org, owner, and enqueues import + welcome jobs" do
    result = nil

    expect { result = described_class.call(code: "oauth-code") }
      .to have_enqueued_job(ImportSlackUsersJob)
      .and have_enqueued_job(SendWelcomeMessageJob)

    expect(result).to be_success

    organization = result.organization
    expect(organization).to be_persisted
    expect(organization.slack_workspace.identifier).to eq("T00000000")

    expect(result.user).to be_owner
    expect(result.user.provider_uid).to eq("U00000000")
    expect(organization.reload.owner).to eq(result.user)
  end

  context "when an already-installed workspace re-runs the install flow" do
    let!(:existing_workspace) { create(:slack_workspace, identifier: "T00000000") }

    it "reuses the org and does not re-run the onboarding jobs" do
      result = nil

      expect { result = described_class.call(code: "oauth-code") }
        .to have_enqueued_job(ImportSlackUsersJob).exactly(0).times
        .and have_enqueued_job(SendWelcomeMessageJob).exactly(0).times

      expect(result).to be_success
      expect(result.organization).to eq(existing_workspace.organization)
      expect(Organization.count).to eq(1)
    end
  end

  context "when the OAuth exchange fails" do
    before do
      allow(Slack::Request::Auth).to receive(:new)
        .and_return(instance_double(Slack::Request::Auth, perform_oauth: nil))
    end

    it "fails without creating an organization" do
      result = described_class.call(code: "bad")

      expect(result).to be_failure
      expect(result.error).to eq(:invalid_response)
      expect(Organization.count).to eq(0)
    end
  end
end
