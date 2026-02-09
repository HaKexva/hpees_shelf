FactoryBot.define do
  factory :book do
    association :batch_year
    sequence(:title) { |n| "Book Title #{n}" }
    sequence(:isbn) { |n| "978000000000#{n}" }
    total { 1 }
    volume { 1 }
    note { "Test note" }
    grade_id { 1 }
  end
end
