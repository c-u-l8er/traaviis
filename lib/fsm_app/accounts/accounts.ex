defmodule FSMApp.Accounts do
  @moduledoc """
  Accounts context: users and authentication (filesystem-backed).
  """

  alias FSMApp.Accounts.User
  alias FSMApp.Storage.FSStore

  @namespace "accounts"
  @users_collection "users"

  def get_user!(id) do
    case Enum.find(load_users(), &(&1["id"] == id)) do
      nil -> raise "User not found"
      map -> to_user_struct(map)
    end
  end

  def get_user_by_email(email) when is_binary(email) do
    case Enum.find(load_users(), &(&1["email"] == email)) do
      nil -> nil
      map -> to_user_struct(map)
    end
  end

  def register_user(attrs) when is_map(attrs) do
    changeset = User.registration_changeset(%User{}, attrs)

    if changeset.valid? do
      email = Ecto.Changeset.get_field(changeset, :email)
      password_hash = Ecto.Changeset.get_field(changeset, :hashed_password)

      case Enum.find(load_users(), &(&1["email"] == email)) do
        nil ->
      now = DateTime.utc_now() |> DateTime.to_iso8601()
          user_map = %{
            "id" => Ecto.UUID.generate(),
            "email" => email,
            "hashed_password" => password_hash,
            "confirmed_at" => nil,
            "inserted_at" => now,
            "updated_at" => now
          }

          case FSStore.persist(@namespace, @users_collection, [user_map | load_users()]) do
            :ok -> {:ok, to_user_struct(user_map)}
            {:error, reason} -> {:error, Ecto.Changeset.add_error(changeset, :base, inspect(reason))}
          end

        _dup ->
          {:error, Ecto.Changeset.add_error(changeset, :email, "has already been taken")}
      end
    else
      {:error, changeset}
    end
  end

  def authenticate_user(email, password) do
    with %User{} = user <- get_user_by_email(email),
         true <- Bcrypt.verify_pass(password, user.hashed_password) do
      {:ok, user}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  # Internal helpers
  defp load_users, do: FSStore.load(@namespace, @users_collection)

  defp to_user_struct(map) when is_map(map) do
    %User{
      id: map["id"],
      email: map["email"],
      hashed_password: map["hashed_password"],
      confirmed_at: map["confirmed_at"],
      inserted_at: normalize_ts(map["inserted_at"]),
      updated_at: normalize_ts(map["updated_at"]) 
    }
  end

  defp normalize_ts(%DateTime{} = dt), do: dt
  defp normalize_ts(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp normalize_ts(_), do: DateTime.utc_now()
end
