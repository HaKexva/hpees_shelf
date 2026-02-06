# frozen_string_literal: true

namespace :school_year do
  desc "Set current_school_year_roc (學年度). In Jul–Sep, run without args to be prompted; or pass the year, e.g. school_year:set[114]"
  task :set, [:roc] => :environment do |_t, args|
    month = Date.current.month
    stored = AppSetting.get("current_school_year_roc").presence&.to_i
    date_based = BatchYear.current_school_year_roc

    if args[:roc].present?
      roc = args[:roc].to_i
      if roc < 1
        puts "Invalid 學年: #{args[:roc]}"
        exit 1
      end
      AppSetting.set("current_school_year_roc", roc)
      puts "Set 目前學年度 to #{roc}學年度."
      next
    end

    if (7..9).cover?(month)
      puts "Currently July–September. Stored 學年度: #{stored || '(not set)'}. Date-based default: #{date_based}."
      print "Which 學年 should it be? (e.g. 114): "
      input = $stdin.gets&.strip
      if input.blank?
        puts "No value entered. Leaving stored value as-is."
        next
      end
      roc = input.to_i
      if roc < 1
        puts "Invalid 學年: #{input}"
        exit 1
      end
      AppSetting.set("current_school_year_roc", roc)
      puts "Set 目前學年度 to #{roc}學年度."
    else
      puts "Current month: #{month}. Stored: #{stored || '(not set)'}. Date-based: #{date_based}."
      puts "To override, run: rails school_year:set[YEAR] (e.g. school_year:set[114])"
    end
  end
end
