require "rails_helper"

RSpec.describe Book do
  let(:batch_year) { create(:batch_year) }
  let(:teacher) { create(:user, :admin, batch_year: batch_year, name: "OwnerTeacher") }
  let(:student) { create(:user, batch_year: batch_year, name: "BorrowerStudent") }

  describe "relocation_behavior (HAK-118)" do
    it "defaults to move_with_class" do
      book = create(:book, batch_year: batch_year, isbn: "9780000000002")
      expect(book.relocation_behavior).to eq("move_with_class")
    end

    it "resets to move_with_class when source is not class" do
      book = build(:book, batch_year: batch_year, source: :donated, relocation_behavior: :stay, isbn: "9780000000019")
      book.valid?
      expect(book.relocation_behavior).to eq("move_with_class")
    end

    it "excludes class stay books from needing_relocation_after_graduated_batch" do
      graduated = create(:batch_year, batch_number: 1, grade_id: BatchYear::GRADE_GRADUATED, is_office: false)
      stay = create(:book, batch_year: graduated, source: :owned_by_class, relocation_behavior: :stay, isbn: "9780000000026")
      move = create(:book, batch_year: graduated, source: :owned_by_class, relocation_behavior: :move_with_class, isbn: "9780000000033")
      donated = create(:book, batch_year: graduated, source: :donated, isbn: "9780000000040")

      ids = Book.needing_relocation_after_graduated_batch.pluck(:id)
      expect(ids).not_to include(stay.id)
      expect(ids).to include(move.id, donated.id)
    end

    it "shifts stay class books to the previous batch without changing grade_id" do
      create(:batch_year, batch_number: 100, grade_id: 5, is_office: false, name: "第100屆")
      curr = create(:batch_year, batch_number: 101, grade_id: BatchYear::GRADE_GRADUATED, is_office: false, name: "第101屆")
      book = create(:book, batch_year: curr, source: :owned_by_class, relocation_behavior: :stay, grade_id: 3, isbn: "9780000000057")
      BatchYear.shift_stay_class_owned_books_to_previous_batch!
      book.reload
      expect(book.batch_year.batch_number).to eq(100)
      expect(book.grade_id).to eq(3)
    end
  end

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
end
