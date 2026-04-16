class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.table_name_prefix
    ENV["DEMO_MODE"] == "1" ? "demo_" : ""
  end
end
