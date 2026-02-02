json.extract! book, :id, :title, :isbn, :total, :volume, :note, :in_need_id, :created_at, :updated_at
json.url book_url(book, format: :json)
