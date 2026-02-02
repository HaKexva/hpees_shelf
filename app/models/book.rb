class Book < ApplicationRecord
  belongs_to :in_need, optional: true
end
