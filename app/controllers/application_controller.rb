class ApplicationController < ActionController::Base
  # Ensure parameter encodings is set (Rails can leave it nil in some load orders, causing has_key? for nil)
  setup_param_encode if instance_variable_get(:@_parameter_encodings).nil?

  def self.inherited(klass)
    super
    klass.setup_param_encode if klass.instance_variable_get(:@_parameter_encodings).nil?
  end

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
