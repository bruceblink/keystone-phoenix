defmodule KeystonePhoenix.Auth.ApiKey.ServiceSubject do
  @moduledoc "PostgreSQL schema for a service subject that owns API credentials."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_service_subject" do
    field :code, :string
    field :name, :string
    field :owner_user_id, :binary_id
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc "校验服务主体的稳定代码和启用状态。"
  def changeset(subject, attrs) do
    subject
    |> cast(attrs, [:id, :code, :name, :owner_user_id, :enabled])
    |> validate_required([:id, :code, :name])
    |> validate_length(:code, max: 128)
    |> validate_length(:name, max: 128)
    |> validate_format(:code, ~r/\Auser:[0-9a-f-]{36}\z/)
    |> foreign_key_constraint(:owner_user_id)
    |> unique_constraint(:code, name: :sys_service_subject_code_unique_index)
  end
end
