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

  describe "teacher-owned book batch_year vs teacher batches" do
    it "rejects when the book 屆數 is not assigned to the owning teacher" do
      by_a = create(:batch_year, batch_number: 501)
      by_b = create(:batch_year, batch_number: 502)
      teacher = create(:user, :admin, batch_year: by_a, name: "T501")
      book = build(
        :book,
        batch_year: by_b,
        source: :owned_by_teacher,
        user: teacher,
        status: Book::STATUS_ON_SHELF,
        isbn: "9780000000095"
      )
      expect(book).not_to be_valid
      expect(book.errors[:batch_year_id]).to be_present
    end

    it "allows when the teacher has the book batch as an extra linked 屆數" do
      by_a = create(:batch_year, batch_number: 511)
      by_b = create(:batch_year, batch_number: 512)
      teacher = create(:user, :admin, batch_year: by_a, extra_batch_years: [ by_b ], name: "T511")
      book = build(
        :book,
        batch_year: by_b,
        source: :owned_by_teacher,
        user: teacher,
        status: Book::STATUS_ON_SHELF,
        isbn: "9780000000088"
      )
      expect(book).to be_valid
    end

    it "allows any batch when the owning teacher is superadmin" do
      by_a = create(:batch_year, batch_number: 521)
      by_b = create(:batch_year, batch_number: 522)
      superuser = create(:user, :superadmin, batch_year: by_a)
      book = build(
        :book,
        batch_year: by_b,
        source: :owned_by_teacher,
        user: superuser,
        status: Book::STATUS_ON_SHELF,
        isbn: "9780000000071"
      )
      expect(book).to be_valid
    end
  end

  describe "#available_for_checkout? / multi-copy non-library" do
    it "is true for donated total 2 when one copy is already borrowed (status 借閱中)" do
      s2 = create(:user, batch_year: batch_year, name: "SecondStudent")
      book = create(
        :book,
        batch_year: batch_year,
        source: :donated,
        total: 2,
        status: Book::STATUS_ON_SHELF,
        isbn: "9780000000071"
      )
      book.checkout_to_borrower!(student)
      book.reload
      expect(book.status).to eq(Book::STATUS_BORROWED)
      expect(book.available_for_checkout?).to be true
      book.checkout_to_borrower!(s2)
      book.reload
      expect(book.available_for_checkout?).to be false
      expect(book.active_loans_count).to eq(2)
    end
  end

  describe "#return_active_loan_for!" do
    it "returns one loan and keeps 借閱中 when another borrower still has a copy (total 2)" do
      s2 = create(:user, batch_year: batch_year, name: "SecondStudent")
      book = create(
        :book,
        batch_year: batch_year,
        source: :donated,
        total: 2,
        status: Book::STATUS_ON_SHELF,
        isbn: "9780000000088"
      )
      book.checkout_to_borrower!(student)
      book.checkout_to_borrower!(s2)
      book.reload
      expect(book.return_active_loan_for!(student)).to be true
      book.reload
      expect(book.status).to eq(Book::STATUS_BORROWED)
      expect(book.borrowed_by?(student)).to be false
      expect(book.borrowed_by?(s2)).to be true
      expect(book.return_active_loan_for!(s2)).to be true
      book.reload
      expect(book.status).to eq(Book::STATUS_ON_SHELF)
    end
  end

  describe "#return_to_library_and_soft_delete! (HAK-75)" do
    it "raises for non-library books" do
      b = create(:book, batch_year: batch_year, source: :donated, isbn: "9780000000064")
      expect { b.return_to_library_and_soft_delete! }.to raise_error(ArgumentError, /only library holdings/)
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
