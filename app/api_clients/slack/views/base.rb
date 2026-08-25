# frozen_string_literal: true

# Base for views.publish / views.open payloads. Subclasses implement #type
# ("home" | "modal") and #blocks. `to_h` is what you pass to
# Slack::Request::OpenView.
class Slack::Views::Base
  include Slack::Blocks

  def type
    raise NotImplementedError, "#{self.class} must implement #type"
  end

  def blocks
    []
  end

  def to_h
    { type: type, blocks: blocks }.compact
  end
  alias_method :as_json, :to_h
end
