# frozen_string_literal: true

class AddNextCallAtToLeads < ActiveRecord::Migration[8.1]
  def change
    add_column :leads, :next_call_at, :datetime
  end
end
