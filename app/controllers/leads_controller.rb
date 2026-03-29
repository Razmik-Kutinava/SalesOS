# frozen_string_literal: true

class LeadsController < ApplicationController
  before_action :require_authentication

  def index
    redirect_to root_path
  end

  def show
    lead = current_user.account.leads.kept.find(params[:id])
    redirect_to root_path(lead_id: lead.id)
  end
end
