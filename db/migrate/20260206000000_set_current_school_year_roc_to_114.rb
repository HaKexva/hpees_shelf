# frozen_string_literal: true

class SetCurrentSchoolYearRocTo114 < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:app_settings)
    AppSetting.set("current_school_year_roc", 114)
  end

  def down
    # Leave value as-is; we don't know the previous value
  end
end
