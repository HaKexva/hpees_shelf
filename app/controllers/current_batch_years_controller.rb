class CurrentBatchYearsController < ApplicationController
  # POST /current_batch_year
  def update
    raw = params[:batch_year_id].to_s.strip

    session[:current_batch_year_id] =
      if raw.blank? || raw == "all"
        "all"
      elsif raw.match?(/\A\d+\z/)
        raw.to_i
      else
        "all"
      end

    redirect_back fallback_location: admin_dashboard_path
  end
end
