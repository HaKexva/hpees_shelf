FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    batch_year
    admin { false }

    trait :admin do
      admin { true }
      sequence(:email) { |n| "admin#{n}@example.com" }
    end

    trait :superadmin do
      admin { true }
      email { User::SUPERADMIN_EMAILS.first }
    end
  end
end
