defmodule KeystonePhoenix.Config.SysConfig do
  @moduledoc "PostgreSQL schema for a Keystone system configuration entry."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:config_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_config" do
    field :config_name, :string
    field :config_key, :string
    field :config_options, :string, default: ""
    field :config_value, :string
    field :is_allow_change, :boolean, default: true
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :remark, :string
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :config_name,
      :config_key,
      :config_options,
      :config_value,
      :is_allow_change,
      :remark
    ])
    |> put_new_id()
    |> validate_required([:config_name, :config_key, :config_value, :is_allow_change])
    |> validate_length(:config_name, max: 128)
    |> validate_length(:config_key, max: 128)
    |> validate_length(:config_options, max: 1024)
    |> validate_length(:config_value, max: 256)
    |> validate_length(:remark, max: 128)
    |> validate_config_value()
    |> unique_constraint(:config_key, name: :sys_config_config_key_unique_index)
  end

  # 新配置 ID 使用 UUIDv7，避免由数据库自增序列生成身份。
  defp put_new_id(changeset) do
    if get_field(changeset, :config_id),
      do: changeset,
      else: put_change(changeset, :config_id, KeystonePhoenix.Identity.v7())
  end

  defp validate_config_value(changeset) do
    validate_change(changeset, :config_value, fn :config_value, value ->
      options = parse_options(get_field(changeset, :config_options))

      if options == [] or value in options do
        []
      else
        [config_value: "必须是可选值之一"]
      end
    end)
  end

  defp parse_options(nil), do: []
  defp parse_options(""), do: []

  defp parse_options(raw_options) when is_binary(raw_options) do
    case Jason.decode(raw_options) do
      {:ok, options} when is_list(options) -> Enum.filter(options, &is_binary/1)
      _ -> []
    end
  end

  defp parse_options(_raw_options), do: []
end
