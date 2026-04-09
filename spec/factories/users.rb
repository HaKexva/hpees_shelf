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

    trait :admin do
      admin { true }
      sequence(:email) { |n| "admin#{n}@example.com" }
      after(:build) do |user|
        user.extra_batch_years << user.batch_year if user.extra_batch_years.blank? && user.batch_year.present?
      end
    end

    trait :superadmin do
      admin { true }
      email { User::SUPERADMIN_EMAILS.first }
      after(:build) do |user|
        user.extra_batch_years << user.batch_year if user.extra_batch_years.blank? && user.batch_year.present?
      end
    end
  end
end
