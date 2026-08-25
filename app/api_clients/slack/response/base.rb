class Slack::Response::Base
  def initialize(response)
    @response = response.to_h.with_indifferent_access
  end

  def full_response
    @response
  end

  def success?
    @response[:ok]
  end

  def no_response?
    @response.blank?
  end
end
