defmodule FSMAppWeb.RegistrationHTML do
  use FSMAppWeb, :html

  embed_templates "registration_html/*"

  # Helper function to convert changeset errors for the error_display component
  def changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} ->
      {field, msg}
    end)
  end
end
