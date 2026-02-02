class Batch < ApplicationRecord
  has_many :books, dependent: :nullify
  has_many :users, dependent: :nullify

  validates :name, presence: true
end
