require "rails_helper"

RSpec.describe Book do
  let(:batch_year) { create(:batch_year) }
  let(:teacher) { create(:user, :admin, batch_year: batch_year, name: "OwnerTeacher") }
  let(:student) { create(:user, batch_year: batch_year, name: "BorrowerStudent") }

  describe "#checkout_to_borrower! / #return_from_single_copy_borrow!" do
    it "keeps owning teacher on user_id when a student borrows and returns (HAK-116)" do
      book = create(
        :book,
        batch_year: batch_year,
        source: :owned_by_teacher,
        user: teacher,
        status: Book::STATUS_ON_SHELF,
        isbn: "9780000000002"
      )

      book.checkout_to_borrower!(student)
      book.reload
      expect(book.user_id).to eq(teacher.id)
      expect(book.status).to eq(Book::STATUS_BORROWED)
      expect(book.borrowers).to include(student)

      book.return_from_single_copy_borrow!
      book.reload
      expect(book.user_id).to eq(teacher.id)
      expect(book.status).to eq(Book::STATUS_ON_SHELF)
      expect(book.borrowers).to be_empty
    end

    it "sets user_id to the borrower for donated single-copy checkout" do
      book = create(
        :book,
        batch_year: batch_year,
        source: :donated,
        user: nil,
        isbn: "9780000000019"
      )

      book.checkout_to_borrower!(student)
      book.reload
      expect(book.user_id).to eq(student.id)
      expect(book.borrowers).to include(student)
    end
  end

  describe ".import_teacher_user_from_source_label (HAK-119)" do
    it "returns nil when the label does not match any admin" do
      create(:user, :admin, batch_year: batch_year, name: "SomeoneElse")
      expect(Book.import_teacher_user_from_source_label("幽靈老師的老師的書")).to be_nil
    end

    it "returns the admin user when the name matches" do
      t = create(:user, :admin, batch_year: batch_year, name: "MatchName")
      expect(Book.import_teacher_user_from_source_label("MatchName老師的書")).to eq(t)
    end

    it "returns nil for bare 老師的書" do
      create(:user, :admin, batch_year: batch_year, name: "Any")
      expect(Book.import_teacher_user_from_source_label("老師的書")).to be_nil
    end
  end
end
