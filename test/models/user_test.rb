require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires email" do
    account = create_account!
    user = User.new(
      account: account,
      password: "password",
      password_confirmation: "password",
      role: "user",
      locale: "ru",
      timezone: "UTC"
    )
    assert_not user.valid?
    assert user.errors.key?(:email)
  end

  test "normalizes email to downcase" do
    account = create_account!
    user = create_user!(account, email: "  MixED@TEST.DEV  ")
    assert_equal "mixed@test.dev", user.reload.email
  end

  test "rejects duplicate email in same account" do
    account = create_account!
    create_user!(account, email: "dup@test.dev")
    dup = User.new(
      account: account,
      email: "dup@test.dev",
      password: "password",
      password_confirmation: "password",
      role: "user",
      locale: "ru",
      timezone: "UTC"
    )
    assert_not dup.valid?
    assert dup.errors.key?(:email)
  end

  test "allows same email in different accounts" do
    a1 = create_account!
    a2 = create_account!
    create_user!(a1, email: "shared@test.dev")
    u2 = create_user!(a2, email: "shared@test.dev")
    assert_predicate u2, :persisted?
  end

  test "rejects invalid role" do
    account = create_account!
    user = build_user(account, role: "superadmin")
    assert_not user.valid?
    assert user.errors.key?(:role)
  end

  test "telegram_id must be unique when set" do
    account = create_account!
    create_user!(account, telegram_id: 99_887_766)
    other = build_user(account, telegram_id: 99_887_766)
    assert_not other.valid?
    assert other.errors.key?(:telegram_id)
  end

  private

  def build_user(account, attrs = {})
    suffix = SecureRandom.hex(3)
    User.new({
      account: account,
      email: "b-#{suffix}@test.dev",
      password: "password",
      password_confirmation: "password",
      role: "user",
      locale: "ru",
      timezone: "UTC"
    }.merge(attrs))
  end
end
