class Book < ApplicationRecord
  TAG_LIBRARY = "圖書館的書"
  TAG_DONATED = "捐贈的書"
  TAG_CLASS = "班級的書"
  TAG_TEACHER_PREFIX = "老師的書"
  TAG_FILTER_OPTIONS = [ [ "圖書館的書", TAG_LIBRARY ], [ "捐贈的書", TAG_DONATED ], [ "班級的書", TAG_CLASS ], [ "老師的書", TAG_TEACHER_PREFIX ] ].freeze
end
