FactoryBot.define do
  factory :user do
    association :batch_year
    sequence(:name) { |n| "User #{n}" }
    id_number { nil }
    seat_number { nil }
    admin { false }
    resigned_at { nil }
    deleted_at { nil }
    grade_id { 1 }
    email { nil }
  end
end
