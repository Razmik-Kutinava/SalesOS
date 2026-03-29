ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: false)

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper
    # SQLite использует один файл БД — параллельные воркеры дают database locked.
    # См. test/README.md и docs/troubleshooter при смене БД на PostgreSQL.
    # parallelize(workers: :number_of_processors, with: :threads)

    # Фикстуры не используем; данные создаём в тестах явно.
    # fixtures :all

    def create_account!(attrs = {})
      Account.create!({ name: "Account-#{SecureRandom.hex(4)}" }.merge(attrs))
    end

    def create_user!(account, attrs = {})
      suffix = SecureRandom.hex(4)
      User.create!({
        account: account,
        email: "user-#{suffix}@test.dev",
        password: "password",
        password_confirmation: "password",
        role: "user",
        locale: "ru",
        timezone: "UTC"
      }.merge(attrs))
    end

    def create_lead!(account, attrs = {})
      Lead.create!({ account: account, company_name: "Co-#{SecureRandom.hex(2)}" }.merge(attrs))
    end
  end
end
