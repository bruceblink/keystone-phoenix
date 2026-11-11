defmodule KeystonePhoenix.Config do
  @moduledoc """
  Query and command boundary for system configuration entries.
  """

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo

  @config_cache_ttl 300
  @config_cache_prefix "keystone:system:config:"

  @config_attrs [
    {"configName", :config_name},
    {"configKey", :config_key},
    {"configOptions", :config_options},
    {"configValue", :config_value},
    {"isAllowChange", :is_allow_change},
    {"remark", :remark}
  ]

  @spec list_configs(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_configs(params \\ %{}) do
    query =
      from c in SysConfig,
        where: c.deleted == false,
        order_by: [desc: c.config_id]

    query =
      query
      |> filter_contains(:config_name, params["configName"] || params[:config_name])
      |> filter_equal(:config_key, params["configKey"] || params[:config_key])
      |> filter_allow_change(params["isAllowChange"] || params[:is_allow_change])

    page_query(query, params)
  end

  @spec get_config(integer() | String.t()) :: {:ok, SysConfig.t()} | {:error, :not_found}
  def get_config(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(SysConfig, config_id: id, deleted: false) do
          nil -> {:error, :not_found}
          config -> {:ok, config}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @spec get_config_value_by_key(String.t()) :: String.t()
  def get_config_value_by_key(config_key) when is_binary(config_key) do
    Cache.fetch(config_cache_key(config_key), @config_cache_ttl, fn ->
      case Repo.get_by(SysConfig, config_key: config_key, deleted: false) do
        nil -> ""
        config -> config.config_value || ""
      end
    end)
  end

  def get_config_value_by_key(_config_key), do: ""

  @spec create_config(map()) :: {:ok, SysConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_config(attrs, actor_id \\ nil)

  def create_config(attrs, actor_id) do
    changeset = SysConfig.changeset(%SysConfig{}, normalize_attrs(attrs))
    changeset = Audit.put_actor(changeset, :creator_id, actor_id)

    case Repo.insert(changeset) do
      {:ok, config} = result ->
        Cache.delete(config_cache_key(config.config_key))
        result

      error ->
        error
    end
  end

  @spec update_config(integer() | String.t(), map()) ::
          {:ok, SysConfig.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_config(id, attrs, actor_id \\ nil)

  def update_config(id, attrs, actor_id) do
    with {:ok, config} <- get_config(id) do
      if config.is_allow_change do
        changeset = SysConfig.changeset(config, normalize_attrs(attrs))
        changeset = Audit.put_actor(changeset, :updater_id, actor_id)

        case Repo.update(changeset) do
          {:ok, updated} = result ->
            Cache.delete(config_cache_key(config.config_key))
            Cache.delete(config_cache_key(updated.config_key))
            result

          error ->
            error
        end
      else
        {:error, :not_allow_change}
      end
    end
  end

  @spec refresh_cache() :: :ok
  def refresh_cache, do: Cache.delete_prefix(@config_cache_prefix)

  @spec config_to_map(SysConfig.t()) :: map()
  def config_to_map(config) do
    %{
      "configId" => config.config_id,
      "configName" => config.config_name,
      "configKey" => config.config_key,
      "configValue" => config.config_value,
      "configOptions" => parse_options(config.config_options),
      "isAllowChange" => if(config.is_allow_change, do: 1, else: 0),
      "isAllowChangeStr" => if(config.is_allow_change, do: "是", else: "否"),
      "remark" => config.remark,
      "createTime" => format_datetime(config.create_time)
    }
  end

  defp page_query(query, params) do
    Pagination.page(query, params, :config_id, &config_to_map/1)
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    value = "%#{String.trim(to_string(value))}%"
    where(query, [record], ilike(field(record, ^field), ^value))
  end

  defp filter_equal(query, _field, nil), do: query
  defp filter_equal(query, _field, ""), do: query

  defp filter_equal(query, field, value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp filter_allow_change(query, nil), do: query
  defp filter_allow_change(query, ""), do: query

  defp filter_allow_change(query, value) do
    case normalize_boolean(value) do
      boolean when is_boolean(boolean) ->
        where(query, [record], record.is_allow_change == ^boolean)

      _ ->
        query
    end
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    normalized =
      Enum.reduce(@config_attrs, %{}, fn {json_key, atom_key}, result ->
        cond do
          Map.has_key?(attrs, json_key) -> Map.put(result, atom_key, Map.get(attrs, json_key))
          Map.has_key?(attrs, atom_key) -> Map.put(result, atom_key, Map.get(attrs, atom_key))
          true -> result
        end
      end)

    normalized
    |> normalize_options()
    |> normalize_allow_change()
  end

  defp normalize_options(attrs) do
    case Map.fetch(attrs, :config_options) do
      :error ->
        attrs

      {:ok, nil} ->
        Map.put(attrs, :config_options, "")

      {:ok, options} when is_list(options) ->
        Map.put(attrs, :config_options, Jason.encode!(Enum.map(options, &to_string/1)))

      {:ok, options} when is_binary(options) ->
        attrs

      {:ok, _options} ->
        Map.put(attrs, :config_options, "")
    end
  end

  defp normalize_allow_change(attrs) do
    case Map.fetch(attrs, :is_allow_change) do
      :error -> attrs
      {:ok, value} -> Map.put(attrs, :is_allow_change, normalize_boolean(value))
    end
  end

  defp normalize_boolean(value) when value in [true, 1, "1", "true", "TRUE"], do: true
  defp normalize_boolean(value) when value in [false, 0, "0", "false", "FALSE"], do: false
  defp normalize_boolean(value), do: value

  defp parse_options(nil), do: []
  defp parse_options(""), do: []

  defp parse_options(raw_options) when is_binary(raw_options) do
    case Jason.decode(raw_options) do
      {:ok, options} when is_list(options) -> Enum.filter(options, &is_binary/1)
      _ -> []
    end
  end

  defp parse_options(_raw_options), do: []

  defp config_cache_key(config_key), do: @config_cache_prefix <> config_key

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
