# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Superadmin Ray Chang: set primary 屆數 = 第4屆 when both exist.
by4 = BatchYear.find_by(batch_number: 4)
u = User.find_by(name: "Ray Chang")
if by4 && u && u.batch_year_id != by4.id
  u.update_columns(batch_year_id: by4.id, grade_id: by4.grade_id)
end
