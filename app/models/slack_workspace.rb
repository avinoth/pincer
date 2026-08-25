class SlackWorkspace < ApplicationRecord
  # The only two real secret columns in the schema. Masked in
  # serializable_hash (the shared base both as_json and to_xml build on — see
  # ActiveModel::Serializers::JSON#as_json and ...::Xml#to_xml) so they never
  # leak through *any* structured-serialization path. This matters because
  # RailsAdmin's show/index/export actions each support a JSON/XML format
  # (`render json: @object`, `@objects.to_json`/`.to_xml`) that bypasses the
  # field-level masking configured in config/initializers/rails_admin.rb,
  # which only covers the HTML view (pretty_value/formatted_value) and, for
  # CSV, the export action's own field.export_value path (also covered by
  # that same config — CSVConverter reads through configured fields, not raw
  # attributes, so it was never at risk). Masking at this lower level closes
  # the JSON/XML gap regardless of caller.
  SERIALIZATION_MASKED_ATTRIBUTES = %w[access_token refresh_token].freeze
  SERIALIZATION_MASK = "•" * 12

  validates :organization, :name, :identifier, :access_token, :refresh_token, presence: true
  validates :organization, uniqueness: true

  belongs_to :organization

  def serializable_hash(options = nil)
    super.tap do |hash|
      SERIALIZATION_MASKED_ATTRIBUTES.each { |attr| hash[attr] = SERIALIZATION_MASK if hash.key?(attr) }
    end
  end

  def token_expired?
    return true if access_token_expires_at.blank?

    Time.current > access_token_expires_at
  end

  def update_details_from_slack!(slack_response)
    update!(
      access_token: slack_response.access_token,
      refresh_token: slack_response.refresh_token,
      access_token_expires_at: slack_response.token_expires_at,
    )
  end
end
