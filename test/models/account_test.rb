require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "requires name" do
    account = Account.new(name: "")
    assert_not account.valid?
    assert account.errors.key?(:name)
  end

  test "persists with valid name" do
    account = create_account!(name: "Valid Corp")
    assert_predicate account, :persisted?
    assert_equal "Valid Corp", account.reload.name
  end

  test "cannot destroy account while users exist" do
    account = create_account!
    create_user!(account)
    assert_raises(ActiveRecord::DeleteRestrictionError) { account.destroy! }
  end

  test "cannot destroy account while leads exist" do
    account = create_account!
    create_lead!(account)
    assert_raises(ActiveRecord::DeleteRestrictionError) { account.destroy! }
  end
end
