require "rails_helper"

RSpec.describe BatchYearsHelper, type: :helper do
  describe "incoming grade-1 choice" do
    it "is treated as grade 1 while school-year switch is pending" do
      expect(helper.relocation_choice_grade(BatchYearsHelper::INCOMING_GRADE1_KEY, staged_commit: true)).to eq(1)
    end

    it "prepends the incoming grade-1 option when staged" do
      by = create(:batch_year, batch_number: 11, grade_id: 1)
      opts = helper.relocation_batch_year_select_options([ by ], staged_commit: true)
      expect(opts.first).to eq([ helper.incoming_grade1_option_label, BatchYearsHelper::INCOMING_GRADE1_KEY ])
    end

    it "does not prepend the incoming option after the year has already switched" do
      by = create(:batch_year, batch_number: 11, grade_id: 1)
      opts = helper.relocation_batch_year_select_options([ by ], staged_commit: false)
      expect(opts.map(&:last)).to eq([ by.id ])
    end
  end
end
