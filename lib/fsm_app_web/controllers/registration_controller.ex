defmodule FSMAppWeb.RegistrationController do
  use FSMAppWeb, :controller

  alias FSMApp.Accounts
  alias FSMApp.Tenancy
  alias FSMApp.Accounts.User

  plug :put_layout, false when action in [:new, :create]

  def new(conn, _params) do
    changeset = %User{} |> User.registration_changeset(%{}) |> Map.put(:action, :insert)
    render(conn, :new, page_title: "Create your account", changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    create(conn, user_params)
  end

  def create(conn, %{"email" => email, "password" => password} = attrs) do
    case Accounts.register_user(%{email: email, password: password}) do
      {:ok, user} ->
        tenant_name = String.trim(Map.get(attrs, "tenant_name", ""))
        base_name = if tenant_name == "", do: default_tenant_name(email), else: tenant_name
        base_slug = slugify(base_name)

        with {:ok, tenant} <- ensure_tenant(base_name, base_slug),
             {:ok, _} <- Tenancy.add_member(tenant.id, user.id, :owner) do
          conn
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Welcome! Your tenant is ready.")
          |> redirect(to: ~p"/control-panel")
        else
          {:error, changeset} ->
            conn
            |> put_flash(:error, "Could not create tenant: #{inspect(changeset.errors)}")
            |> render(:new, page_title: "Create your account")
        end

      {:error, changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        conn
        |> put_flash(:error, "Please correct the errors below")
        |> render(:new, page_title: "Create your account", changeset: changeset)
    end
  end

  defp default_tenant_name(email) do
    local = email |> String.split("@") |> List.first()
    "#{local}'s Space"
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp ensure_tenant(name, slug) do
    case Tenancy.create_tenant(%{name: name, slug: slug}) do
      {:ok, tenant} -> {:ok, tenant}
      {:error, _} ->
        alt_slug = slug <> "-" <> Integer.to_string(System.unique_integer([:positive]))
        Tenancy.create_tenant(%{name: name, slug: alt_slug})
    end
  end

  defp humanize_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} ->
      field = field |> to_string() |> String.replace("_", " ")
      "#{field} #{msg}"
    end)
    |> Enum.join(", ")
  end
end
