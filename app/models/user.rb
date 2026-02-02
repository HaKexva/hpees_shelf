class User < ApplicationRecord
  belongs_to :batch, optional: true
end
