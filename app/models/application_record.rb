class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  shards = { default: { writing: :primary } }
  if ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary_shard_demo").any?
    shards[:demo] = { writing: :primary_shard_demo }
  end
  connects_to shards: shards
end
