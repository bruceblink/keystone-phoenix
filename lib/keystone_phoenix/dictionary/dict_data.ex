defmodule KeystonePhoenix.Dictionary.DictData do
  @moduledoc "PostgreSQL schema for a Keystone dictionary item."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dict_code, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_dict_data" do
    field :dict_type, :string
    field :dict_label, :string
    field :dict_value, :string
    field :dict_sort, :integer, default: 0
    field :is_default, :boolean, default: false
    field :css_class, :string
    field :list_class, :string
    field :status, :integer, default: 1
    field :remark, :string
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(dict_data, attrs) do
    attrs = normalize_value(attrs)

    dict_data
    |> cast(attrs, [
      :dict_type,
      :dict_label,
      :dict_value,
      :dict_sort,
      :is_default,
      :css_class,
      :list_class,
      :status,
      :remark
    ])
    |> put_new_id()
    |> validate_required([:dict_type, :dict_label, :dict_value, :status])
    |> validate_length(:dict_type, max: 100)
    |> validate_length(:dict_value, max: 128)
    |> validate_length(:dict_label, max: 100)
    |> validate_length(:css_class, max: 100)
    |> validate_length(:list_class, max: 100)
    |> validate_length(:remark, max: 500)
    |> validate_inclusion(:status, [0, 1])
  end

  # Native 使用字符串值；兼容旧 LiveView 和种子中的数字输入后再写入字符串列。
  defp normalize_value(attrs) when is_map(attrs) do
    case Map.get(attrs, :dict_value, Map.get(attrs, "dictValue")) do
      value when is_integer(value) -> Map.put(attrs, :dict_value, Integer.to_string(value))
      value when is_float(value) -> Map.put(attrs, :dict_value, to_string(value))
      _ -> attrs
    end
  end

  defp normalize_value(attrs), do: attrs

  # 新字典数据 ID 使用 UUIDv7；dict_type 仍使用稳定业务编码关联类型。
  defp put_new_id(changeset) do
    if get_field(changeset, :dict_code),
      do: changeset,
      else: put_change(changeset, :dict_code, KeystonePhoenix.Identity.v7())
  end
end
