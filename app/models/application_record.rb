class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  connects_to shards: {
    default: { writing: :primary },
    demo: { writing: :primary_shard_demo }
  }
end
