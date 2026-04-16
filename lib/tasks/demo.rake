namespace :demo do
  desc "Seed demo tables with sample data"
  task seed: :environment do
    unless ENV["DEMO_MODE"] == "1"
      puts "Setting DEMO_MODE=1 for seeding..."
      ENV["DEMO_MODE"] = "1"
      ActiveRecord::Base.clear_all_connections!
    end

    puts "Seeding demo data..."

    # Create batch years (grades 1-6)
    batch_years = []
    6.times do |i|
      batch_years << BatchYear.find_or_create_by!(batch_number: i + 1) do |by|
        by.grade_id = 6 - i
        by.name = "第#{i + 1}屆"
      end
    end
    puts "Created #{batch_years.size} batch years"

    # Create demo admin
    demo_admin = User.find_or_create_by!(email: "demo@example.com") do |u|
      u.name = "Demo 管理員"
      u.admin = true
      u.batch_year = batch_years.first
      u.grade_id = batch_years.first.grade_id
    end
    puts "Created demo admin: #{demo_admin.name}"

    # Create some students
    students = []
    batch_years.each_with_index do |by, idx|
      3.times do |j|
        students << User.find_or_create_by!(
          name: "學生#{idx + 1}-#{j + 1}",
          batch_year: by
        ) do |u|
          u.admin = false
          u.grade_id = by.grade_id
          u.seat_number = format("%02d", j + 1)
        end
      end
    end
    puts "Created #{students.size} students"

    # Create some books with valid ISBN-13 codes
    book_data = [
      { title: "小王子", isbn: "9780000000019" },
      { title: "哈利波特：神秘的魔法石", isbn: "9780000000026" },
      { title: "好餓的毛毛蟲", isbn: "9780000000033" },
      { title: "愛麗絲夢遊仙境", isbn: "9780000000040" },
      { title: "乘風破浪", isbn: "9780000000057" },
      { title: "勇敢的小熊", isbn: "9780000000064" }
    ]

    books = []
    book_data.each_with_index do |data, idx|
      by = batch_years[idx % batch_years.size]
      book = Book.find_by(title: data[:title])
      unless book
        book = Book.new(
          title: data[:title],
          isbn: data[:isbn],
          batch_year: by,
          grade_id: by.grade_id,
          source: idx < 3 ? :owned_by_class : :donated,
          status: "架上"
        )
        unless book.save
          puts "Book validation failed: #{book.errors.full_messages.join(', ')}"
          next
        end
      end
      books << book
    end
    puts "Created #{books.size} books"

    # Set school year
    AppSetting.find_or_create_by!(key: "stored_school_year") do |s|
      s.value = "113"
    end

    puts "Demo data seeding complete!"
  end

  desc "Reset demo tables (clear and reseed)"
  task reset: :environment do
    unless ENV["DEMO_MODE"] == "1"
      puts "Setting DEMO_MODE=1 for reset..."
      ENV["DEMO_MODE"] = "1"
      ActiveRecord::Base.clear_all_connections!
    end

    puts "Clearing demo tables..."
    CirculationRecord.delete_all
    LibraryLoanHistory.delete_all
    Book.unscoped.delete_all
    User.unscoped.delete_all
    BatchYear.delete_all
    AppSetting.delete_all

    Rake::Task["demo:seed"].reenable
    Rake::Task["demo:seed"].invoke
  end
end
