FactoryBot.define do
  factory :book do
    association :batch_year
    sequence(:title) { |n| "Book Title #{n}" }
    sequence(:isbn) do |n|
      base = "978000000%03d" % n  # 12 digits
      digits = base.chars.map(&:to_i)
      weights = [1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3]
      sum = digits.zip(weights).sum { |d, w| d * w }
      check = (10 - (sum % 10)) % 10
      "#{base}#{check}"
    end
    total { 1 }
    volume { 1 }
    note { "Test note" }
    grade_id { 1 }
  end
end
