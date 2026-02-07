# frozen_string_literal: true

# Workaround: Rails can leave @_parameter_encodings nil on some controller classes
# (e.g. load order), causing NoMethodError (undefined method 'has_key?' for nil).
# Ensure it is always a Hash before use.
Rails.application.config.after_initialize do
  ActionController::ParameterEncoding::ClassMethods.module_eval do
    def action_encoding_template(action)
      @_parameter_encodings ||= Hash.new { |h, k| h[k] = {} }
      if @_parameter_encodings.has_key?(action.to_s)
        @_parameter_encodings[action.to_s]
      end
    end
  end
end
