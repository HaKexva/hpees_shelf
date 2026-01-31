module Components
  class Base < Phlex::HTML
    include Components
    include RubyUI
    include Phlex::Rails::Helpers::Routes

    if Rails.env.development?
      def before_template
        comment { "Before #{self.class.name}" }
        super
      end
    end
  end
end
