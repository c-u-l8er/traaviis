defmodule FSMAppWeb.RegistrationController do
  use FSMAppWeb, :controller

  alias FSMApp.Accounts
  alias FSMApp.Tenancy
  alias FSMApp.Accounts.User
  alias FSMAppWeb.Auth.AuthHelpers
  alias FSMAppWeb.Auth.Guardian

  plug :put_layout, false when action in [:new, :create]

  def new(conn, _params) do
    changeset = %User{} |> User.registration_changeset(%{})
    render(conn, :new, page_title: "Create your account", changeset: changeset, form_data: %{email: "", password: "", tenant_name: ""})
  end

  def create(conn, %{"user" => user_params}) do
    create(conn, user_params)
  end

  def create(conn, %{"email" => email, "password" => password} = attrs) do
    tenant_name = String.trim(Map.get(attrs, "tenant_name", ""))
    form_data = %{email: email, password: "", tenant_name: tenant_name}

    case Accounts.register_user(%{email: email, password: password}) do
      {:ok, user} ->
        base_name = if tenant_name == "", do: default_tenant_name(email), else: tenant_name
        base_slug = slugify(base_name)

        with {:ok, tenant} <- ensure_tenant(base_name, base_slug),
             {:ok, _} <- Tenancy.add_member(tenant.id, user.id, :owner) do
          # Authenticate user properly with Guardian (same as SessionController)
          case AuthHelpers.create_auth_token(user) do
            {:ok, token, _claims} ->
              conn
              |> Guardian.Plug.sign_in(user)
              |> AuthHelpers.put_auth_session(user, token)
              |> put_flash(:info, "Welcome! Your account has been created.")
              |> redirect(to: ~p"/control-panel")

            {:error, token_error} ->
              # Fallback: sign in with Guardian directly if token helper fails
              conn
              |> Guardian.Plug.sign_in(user)
              |> put_session(:user_id, user.id)
              |> put_flash(:info, "Welcome! Your account has been created.")
              |> redirect(to: ~p"/control-panel")
          end
        else
          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not create organization: #{inspect(reason)}")
            |> render(:new, page_title: "Create your account",
                changeset: %User{} |> User.registration_changeset(%{}),
                form_data: form_data)
        end

      {:error, changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        conn
        |> put_flash(:error, "Please correct the errors below")
        |> render(:new, page_title: "Create your account", changeset: changeset, form_data: form_data)
    end
  end

  # Handle case where form data is malformed or missing
  def create(conn, _params) do
    changeset = %User{} |> User.registration_changeset(%{}) |> Map.put(:action, :insert)
    conn
    |> put_flash(:error, "Please provide all required information")
    |> render(:new, page_title: "Create your account",
        changeset: changeset,
        form_data: %{email: "", password: "", tenant_name: ""})
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
