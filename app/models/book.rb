class Book < ApplicationRecord
  belongs_to :batch, optional: true
end
