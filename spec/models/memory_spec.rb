require "rails_helper"

RSpec.describe Memory do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:user).optional }
  it { is_expected.to belong_to(:source_conversation).class_name("Conversation").optional }

  it { is_expected.to validate_presence_of(:content) }

  describe ".org_scoped" do
    it "returns only memories without a user" do
      org_memory = create(:memory, user: nil)
      create(:memory, user: create(:user, organization: org_memory.organization))

      expect(described_class.org_scoped).to contain_exactly(org_memory)
    end
  end

  describe ".for_user" do
    it "returns only memories for the given user" do
      organization = create(:organization)
      user = create(:user, organization: organization)
      user_memory = create(:memory, organization: organization, user: user)
      create(:memory, organization: organization, user: nil)
      create(:memory, organization: organization, user: create(:user, organization: organization))

      expect(described_class.for_user(user)).to contain_exactly(user_memory)
    end
  end

  describe ".active" do
    it "returns only active memories" do
      active = create(:memory, active: true)
      create(:memory, active: false)

      expect(described_class.active).to contain_exactly(active)
    end
  end
end
