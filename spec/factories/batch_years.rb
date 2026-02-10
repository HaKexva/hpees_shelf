FactoryBot.define do
  factory :batch_year do
    sequence(:batch_number) { |n| n }
    grade_id { 1 }
    sequence(:name) { |n| "第#{n}屆" }
  end
end
