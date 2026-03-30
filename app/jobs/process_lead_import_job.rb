# frozen_string_literal: true

class ProcessLeadImportJob < ApplicationJob
  queue_as :default

  def perform(lead_import_id)
    lead_import = LeadImport.find_by(id: lead_import_id)
    return unless lead_import

    Imports::LeadImportProcessor.call(lead_import)
  end
end
