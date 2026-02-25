FactoryBot.define do
  factory :book do
    association :batch_year
    sequence(:title) { |n| "Book Title #{n}" }
    isbn { "9789861817286" }
    total { 1 }
    volume { 1 }
    note { "Test note" }
    grade_id { 1 }
  end
end
