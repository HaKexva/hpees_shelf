require "rails_helper"

RSpec.describe "Batch year school-year switch", type: :request do
  let(:batch_year) { create(:batch_year) }
  let(:admin) { create(:user, :superadmin, batch_year: batch_year) }
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_cache)
    login_as(admin)
  end

  it "keeps a large pending-book list out of the cookie session" do
    book_ids = (1..1120).to_a
    allow_any_instance_of(BatchYearsController)
      .to receive(:dry_run_relocation_pending_ids)
      .and_return([ book_ids, [ admin.id ] ])

    post reassign_grades_batch_years_path

    expect(response).to redirect_to(relocation_batch_years_path)
    expect(response).to have_http_status(:see_other)
    expect(session[:pending_relocation_book_ids]).to be_blank
    expect(session[:pending_relocation_user_ids]).to be_blank
    expect(session[:relocation_draft]).to be_blank

    stored = Rails.cache.read("relocation_workflow/main/#{admin.id}")
    expect(stored["pending_book_ids"].size).to eq(1120)
    expect(stored["pending_user_ids"]).to eq([ admin.id ])
    expect(stored["pending_commit"]).to eq(true)
  end
end
