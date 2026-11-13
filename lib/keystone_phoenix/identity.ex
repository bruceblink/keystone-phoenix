defmodule KeystonePhoenix.Identity do
  @moduledoc """
  提供身份标识的统一生成、校验和 PostgreSQL UUID 边界转换。

  新业务实体使用 UUIDv7。固定权限目录使用 UUIDv5。应用层传递规范小写
  连字符字符串，Ecto 在数据库边界使用 16 字节原始 UUID。
  """

  import Bitwise

  @permission_namespace "eb754ae2-49de-5e5f-87ef-1fa5eded86d8"
  @canonical_uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @permission ~r/\A[a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9-]*\z/

  @type uuid :: String.t()

  @doc "返回固定权限目录使用的 UUIDv5 命名空间。"
  @spec permission_namespace() :: uuid()
  def permission_namespace, do: @permission_namespace

  @doc "生成规范小写连字符 UUIDv7。随机源失败时直接抛出异常。"
  @spec v7() :: uuid()
  def v7, do: Ecto.UUID.generate(version: 7)

  @doc "根据规范命名空间和 UTF-8 名称生成 UUIDv5。"
  @spec v5(uuid(), String.t()) :: uuid()
  def v5(namespace, name) when is_binary(namespace) and is_binary(name) do
    namespace_binary = namespace |> canonical!() |> Ecto.UUID.dump!()
    digest = :crypto.hash(:sha, [namespace_binary, name])

    <<time_low::32, time_mid::16, time_and_version::16, clock_sequence::16, node::48, _::32>> =
      digest

    versioned = (time_and_version &&& 0x0FFF) ||| 0x5000
    variant = (clock_sequence &&& 0x3FFF) ||| 0x8000

    <<time_low::32, time_mid::16, versioned::16, variant::16, node::48>>
    |> Ecto.UUID.load!()
  end

  @doc "生成权限目录的稳定 UUIDv5。名称格式固定为 permission:<resource>:<action>。"
  @spec permission_id(String.t()) :: uuid()
  def permission_id(permission) when is_binary(permission) do
    if Regex.match?(@permission, permission) do
      v5(@permission_namespace, "permission:" <> permission)
    else
      raise ArgumentError, "permission must use resource:action format"
    end
  end

  @doc "判断字符串是否为规范小写连字符 UUID。"
  @spec canonical?(term()) :: boolean()
  def canonical?(value) when is_binary(value), do: Regex.match?(@canonical_uuid, value)
  def canonical?(_value), do: false

  @doc "校验并返回规范小写连字符 UUID。"
  @spec canonical!(term()) :: uuid()
  def canonical!(value) do
    if canonical?(value) do
      value
    else
      raise ArgumentError, "uuid must use lowercase canonical format"
    end
  end

  @doc "把规范字符串转换为 PostgreSQL uuid 类型使用的 16 字节值。"
  @spec dump(term()) :: {:ok, binary()} | :error
  def dump(value) do
    if canonical?(value), do: Ecto.UUID.dump(value), else: :error
  end

  @doc "把 PostgreSQL uuid 类型返回的 16 字节值转换为规范字符串。"
  @spec load(term()) :: {:ok, uuid()} | :error
  def load(value) do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> {:ok, canonical!(uuid)}
      :error -> :error
    end
  end
end
