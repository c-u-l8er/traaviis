alias FSMApp.Accounts
alias FSMApp.Tenancy

{:ok, user} = Accounts.register_user(%{email: "admin@example.com", password: "VeryStrongPassword"})
{:ok, tenant} = Tenancy.create_tenant(%{name: "Acme Corp", slug: "acme"})
{:ok, _m} = Tenancy.add_member(tenant.id, user.id, :owner)
