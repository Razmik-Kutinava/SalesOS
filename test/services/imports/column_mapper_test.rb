# frozen_string_literal: true

require "test_helper"

class Imports::ColumnMapperTest < ActiveSupport::TestCase
  test "heuristic maps Russian and English headers" do
    headers = [ "Company Name", "E-mail", "Телефон", "Контакт" ]
    m = Imports::ColumnMapper.heuristic(headers)
    assert_equal "Company Name", m["company_name"]
    assert_equal "E-mail", m["email"]
    assert_equal "Телефон", m["phone"]
    assert_equal "Контакт", m["contact_name"]
  end
end
