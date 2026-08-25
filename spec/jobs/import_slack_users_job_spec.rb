require "rails_helper"

RSpec.describe ImportSlackUsersJob do
  let(:organization) { create(:organization, users_import_status: :pending) }

  it "marks import completed on success" do
    allow(ImportUsersFromSlack).to receive(:call).and_return(double(failure?: false))

    described_class.perform_now(organization.id)

    expect(organization.reload).to be_users_import_completed
  end

  it "marks import failed on failure" do
    allow(ImportUsersFromSlack).to receive(:call).and_return(double(failure?: true, error: :boom))

    described_class.perform_now(organization.id)

    expect(organization.reload).to be_users_import_failed
  end

  it "no-ops for a missing organization" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
