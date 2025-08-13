defmodule FSMApp.Accounts.User do
  @moduledoc """
  User schema.
  """

  use FSMApp.Schema

  @derive {Jason.Encoder, only: [:id, :email, :inserted_at, :updated_at]}
  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :confirmed_at, :utc_datetime

    has_many :memberships, FSMApp.Tenancy.Membership

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^\S+@\S+$/)
    |> unique_constraint(:email)
    |> validate_length(:password, min: 10)
    |> put_password_hash()
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, hashed_password: Bcrypt.hash_pwd_salt(password))
  end

  defp put_password_hash(changeset), do: changeset
end
