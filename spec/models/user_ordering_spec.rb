require "rails_helper"

RSpec.describe User, type: :model do
  describe ".ordered_for_list" do
    let(:batch_year) { create(:batch_year) }

    it "puts nil id_number first when sorting by id_number" do
      nil_user = create(:user, batch_year: batch_year, id_number: nil, seat_number: "2", name: "Nil ID")
      has_user = create(:user, batch_year: batch_year, id_number: "123456", seat_number: "1", name: "Has ID")

      ids = User.where(id: [ nil_user.id, has_user.id ]).ordered_for_list("id_number").pluck(:id)
      expect(ids.first).to eq(nil_user.id)
    end

    it "puts nil seat_number first when sorting by seat_number" do
      nil_user = create(:user, batch_year: batch_year, seat_number: nil, id_number: "123456", name: "Nil Seat")
      has_user = create(:user, batch_year: batch_year, seat_number: "1", id_number: "654321", name: "Has Seat")

      ids = User.where(id: [ nil_user.id, has_user.id ]).ordered_for_list("seat_number").pluck(:id)
      expect(ids.first).to eq(nil_user.id)
    end
  end
end

