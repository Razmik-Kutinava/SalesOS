# Seeds are idempotent: safe to run multiple times.
account = Account.find_or_create_by!(name: "Demo") do |a|
  a.settings = {}
end

user = User.find_or_create_by!(account: account, email: "admin@example.com") do |u|
  u.password = "password"
  u.password_confirmation = "password"
  u.role = "owner"
  u.locale = "ru"
  u.timezone = "UTC"
end

# Только среди активных (kept): после удаления лида сид снова создаст демо.
unless account.leads.kept.exists?(company_name: "Demo Lead")
  account.leads.create!(
    company_name: "Demo Lead",
    stage: "new",
    source: "manual",
    score: 0,
    owner: user
  )
end
