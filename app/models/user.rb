class User < ApplicationRecord
  has_many :books, dependent: :nullify
end
