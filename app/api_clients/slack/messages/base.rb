# frozen_string_literal: true

# Base for chat.postMessage payloads. Subclasses implement #blocks (Block Kit) and
# should provide a #text fallback (shown in notifications and by clients that can't
# render blocks). `to_h` is what you pass to Slack::Request::SendMessage#send_message.
class Slack::Messages::Base
  include Slack::Blocks

  def text
    nil
  end

  def blocks
    []
  end

  def color
    nil
  end

  def to_h
    if color.present?
      { text: text, attachments: [ { color: color, blocks: blocks.presence }.compact ] }.compact
    else
      { text: text, blocks: blocks.presence }.compact
    end
  end
  alias_method :as_json, :to_h
end
