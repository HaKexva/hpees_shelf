class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  shards = { default: { writing: :primary } }
  demo_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary_shard_demo")
  if demo_config.respond_to?(:any?) ? demo_config.any? : !!demo_config
    shards[:demo] = { writing: :primary_shard_demo }
  end
  connects_to shards: shards
end
