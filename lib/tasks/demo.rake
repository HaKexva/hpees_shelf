# frozen_string_literal: true

namespace :demo do
  desc "Seed demo data (runs in demo shard). Idempotent via find_or_create_by!."
  task seed: :environment do
    ActiveRecord::Base.connected_to(shard: :demo) do
      batch1 =
        BatchYear.find_or_create_by!(batch_number: 1) do |by|
          by.grade_id = 1
          by.name = "第1屆"
          by.is_office = false
        end

      BatchYear.find_or_create_by!(batch_number: 2) do |by|
        by.grade_id = 2
        by.name = "第2屆"
        by.is_office = false
      end

      demo_admin =
        User.find_or_create_by!(email: "demo-admin@example.com") do |u|
          u.name = "示範管理員"
          u.admin = true
          u.batch_year = batch1
        end

      5.times do |i|
        n = i + 1
        User.find_or_create_by!(email: format("demo-student-%02d@example.com", n)) do |u|
          u.name = "示範學生#{n}"
          u.admin = false
          u.batch_year = batch1
          u.seat_number = n.to_s
          u.id_number = format("%06d", n)
        end
      end

      samples = [
        { title: "示範書籍 A", isbn: "9789861817286", call_number: "00000001", source: :owned_by_library },
        { title: "示範書籍 B", isbn: "9789861817293", call_number: "00000002", source: :owned_by_library },
        { title: "示範書籍 C", isbn: "9789861817309", call_number: "00000003", source: :owned_by_library },
        { title: "捐贈書籍 D", isbn: "9789861817316", call_number: nil, source: :donated },
        { title: "班級書籍 E", isbn: "9789861817323", call_number: nil, source: :owned_by_class }
      ]

      samples.each_with_index do |attrs, idx|
        Book.find_or_create_by!(isbn: attrs[:isbn], title: attrs[:title], batch_year_id: batch1.id) do |b|
          b.source = attrs[:source]
          b.call_number = attrs[:call_number]
          b.total = 1
          b.volume = ""
          b.note = "demo seed ##{idx + 1}"
          b.user = nil
        end
      end

      puts "Demo seeded (demo shard). Admin: #{demo_admin.email}, students: #{User.where(admin: false).count}, books: #{Book.count}"
    end
  end

  desc "Reset demo data (TRUNCATE CASCADE in demo shard) then reseed."
  task reset: :environment do
    ActiveRecord::Base.connected_to(shard: :demo) do
      conn = ActiveRecord::Base.connection
      tables = conn.tables - %w[schema_migrations ar_internal_metadata]

      if tables.empty?
        puts "No tables to truncate."
      else
        conn.disable_referential_integrity do
          conn.execute("TRUNCATE TABLE #{tables.map { |t| conn.quote_table_name(t) }.join(', ')} RESTART IDENTITY CASCADE")
        end
        puts "Truncated demo tables: #{tables.join(', ')}"
      end
    end

    Rake::Task["demo:seed"].invoke
  end
end

