# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "admin clears 學號 / 座號" do
  let(:batch_year) { create(:batch_year) }

  it "clears id_number and seat_number before validation when admin" do
    u = build(:user, :admin, batch_year: batch_year, id_number: "123456", seat_number: "5", email: "admin-clear@example.com")
    expect(u).to be_valid
    expect(u.id_number).to be_nil
    expect(u.seat_number).to be_nil
  end

  it "clears stored id_number and seat_number when promoted to admin" do
    u = create(:user, batch_year: batch_year, id_number: "111111", seat_number: "1")
    u.update!(admin: true, email: "promoted@example.com")
    u.reload
    expect(u.id_number).to be_nil
    expect(u.seat_number).to be_nil
  end
end
