# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "batch access for borrowing" do
  let(:by1) { create(:batch_year, batch_number: 601) }
  let(:by2) { create(:batch_year, batch_number: 602) }

  describe "#member_batch_year_ids" do
    it "includes primary and extra batch years for admins" do
      u = create(:user, :admin, batch_year: by1, extra_batch_years: [ by2 ])
      expect(u.member_batch_year_ids).to contain_exactly(by1.id, by2.id)
    end
  end

  describe "#may_borrow_from_batch?" do
    it "is true only for linked batches" do
      u = create(:user, :admin, batch_year: by1, extra_batch_years: [ by2 ])
      expect(u.may_borrow_from_batch?(by1.id)).to be true
      expect(u.may_borrow_from_batch?(by2.id)).to be true
      expect(u.may_borrow_from_batch?(create(:batch_year, batch_number: 999).id)).to be false
    end

    it "is true for any batch when superadmin" do
      u = create(:user, :superadmin, batch_year: by1)
      other = create(:batch_year, batch_number: 888)
      expect(u.may_borrow_from_batch?(other.id)).to be true
    end
  end

  describe "primary batch change for admins" do
    it "adds the previous primary 屆數 to extra_batch_years when batch_year_id changes" do
      u = create(:user, :admin, batch_year: by1)
      u.update!(batch_year_id: by2.id)
      u.reload
      expect(u.batch_year_id).to eq(by2.id)
      expect(u.extra_batch_year_ids).to include(by1.id)
    end

    it "does not duplicate when the old primary was already linked as extra" do
      u = create(:user, :admin, batch_year: by1, extra_batch_years: [ by2 ])
      u.update!(batch_year_id: by2.id)
      u.reload
      expect(u.extra_batch_year_ids).to contain_exactly(by1.id, by2.id)
    end

    it "does not add extras when a non-admin primary batch changes" do
      u = create(:user, admin: false, batch_year: by1)
      u.update!(batch_year_id: by2.id)
      u.reload
      expect(u.extra_batch_year_ids).to be_empty
    end
  end

  describe "#teaching_batch_year_ids" do
    it "excludes graduated 屆數 from the two-or-more teaching count" do
      graduated = create(:batch_year, batch_number: 500, grade_id: BatchYear::GRADE_GRADUATED)
      current = create(:batch_year, batch_number: 603, grade_id: 3)
      u = create(:user, :admin, batch_year: current, extra_batch_years: [ graduated ])
      expect(u.member_batch_year_ids).to contain_exactly(current.id, graduated.id)
      expect(u.teaching_batch_year_ids).to contain_exactly(current.id)
      expect(u.multi_cohort_teacher?).to be false
    end

    it "treats current grade 6 as graduated after school-year advance" do
      g6 = create(:batch_year, batch_number: 604, grade_id: 6)
      g5 = create(:batch_year, batch_number: 605, grade_id: 5)
      u = create(:user, :admin, batch_year: g5, extra_batch_years: [ g6 ])
      expect(u.multi_cohort_teacher?).to be true
      expect(u.multi_cohort_teacher?(after_school_year_advance: true)).to be false
    end
  end
end
