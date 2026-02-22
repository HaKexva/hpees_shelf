FactoryBot.define do
  factory :circulation_record do
    association :book
    association :user
    borrowed_at { Time.current }
  end
end
