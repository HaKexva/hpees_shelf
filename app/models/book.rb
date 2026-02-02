class Book < ApplicationRecord
  belongs_to :batch_year, optional: true
end
