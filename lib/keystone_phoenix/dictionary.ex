defmodule KeystonePhoenix.Dictionary do
  @moduledoc """
  Query boundary for the PostgreSQL-backed Keystone dictionary tables.
  """

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Dictionary.{DictData, DictType}
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo

  @dict_data_cache_ttl 300

  @dict_type_attrs [
    {"dictName", :dict_name},
    {"dictType", :dict_type},
    {"status", :status},
    {"remark", :remark}
  ]

  @dict_data_attrs [
    {"dictType", :dict_type},
    {"dictLabel", :dict_label},
    {"dictValue", :dict_value},
    {"dictSort", :dict_sort},
    {"isDefault", :is_default},
    {"cssClass", :css_class},
    {"listClass", :list_class},
    {"status", :status},
    {"remark", :remark}
  ]

  @spec get_dict_type(integer() | String.t()) :: {:ok, DictType.t()} | {:error, :not_found}
  def get_dict_type(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(DictType, dict_id: id, deleted: false) do
          nil -> {:error, :not_found}
          dict_type -> {:ok, dict_type}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @spec get_dict_data(integer() | String.t()) :: {:ok, DictData.t()} | {:error, :not_found}
  def get_dict_data(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(DictData, dict_code: id, deleted: false) do
          nil -> {:error, :not_found}
          dict_data -> {:ok, dict_data}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @spec create_dict_type(map(), keyword()) :: {:ok, DictType.t()} | {:error, term()}
  def create_dict_type(attrs, options)

  def create_dict_type(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:add") do
      do_create_dict_type(attrs, Command.actor_id(options))
    end
  end

  def create_dict_type(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_dict_type(attrs, actor_id) do
    changeset = DictType.changeset(%DictType{}, normalize_attrs(attrs, @dict_type_attrs))
    Repo.insert(Audit.put_actor(changeset, :creator_id, actor_id))
  end

  @spec update_dict_type(integer() | String.t(), map(), keyword()) ::
          {:ok, DictType.t()} | {:error, term()}
  def update_dict_type(id, attrs, options)

  def update_dict_type(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:edit") do
      do_update_dict_type(id, attrs, Command.actor_id(options))
    end
  end

  def update_dict_type(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_dict_type(id, attrs, actor_id) do
    with {:ok, dict_type} <- get_dict_type(id) do
      changeset = DictType.changeset(dict_type, normalize_attrs(attrs, @dict_type_attrs))
      changeset = Audit.put_actor(changeset, :updater_id, actor_id)

      if changeset.valid? do
        old_dict_type = dict_type.dict_type

        case Repo.transaction(fn ->
               case Repo.update(changeset) do
                 {:ok, updated} ->
                   if old_dict_type != updated.dict_type do
                     from(d in DictData,
                       where: d.dict_type == ^old_dict_type and d.deleted == false
                     )
                     |> Repo.update_all(
                       set: [dict_type: updated.dict_type, update_time: DateTime.utc_now()]
                     )
                   end

                   updated

                 {:error, update_changeset} ->
                   Repo.rollback(update_changeset)
               end
             end) do
          {:ok, updated} ->
            Cache.delete(dict_data_cache_key(old_dict_type))
            Cache.delete(dict_data_cache_key(updated.dict_type))
            {:ok, updated}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
      else
        {:error, changeset}
      end
    end
  end

  @spec delete_dict_type(integer() | String.t(), keyword()) :: :ok | {:error, term()}
  def delete_dict_type(id, options)

  def delete_dict_type(id, options) when is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:remove") do
      do_delete_dict_type(id)
    end
  end

  def delete_dict_type(_id, _options), do: {:error, :authorization_required}

  defp do_delete_dict_type(id) do
    with {:ok, dict_type} <- get_dict_type(id) do
      data_count =
        from(d in DictData,
          where: d.dict_type == ^dict_type.dict_type and d.deleted == false
        )
        |> Repo.aggregate(:count, :dict_code)

      if data_count > 0 do
        {:error, :has_data}
      else
        case Repo.update(Ecto.Changeset.change(dict_type, deleted: true)) do
          {:ok, _deleted} ->
            Cache.delete(dict_data_cache_key(dict_type.dict_type))
            :ok

          {:error, _changeset} ->
            {:error, :not_found}
        end
      end
    end
  end

  @spec create_dict_data(map(), keyword()) :: {:ok, DictData.t()} | {:error, term()}
  def create_dict_data(attrs, options)

  def create_dict_data(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:add") do
      do_create_dict_data(attrs, Command.actor_id(options))
    end
  end

  def create_dict_data(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_dict_data(attrs, actor_id) do
    attrs = normalize_attrs(attrs, @dict_data_attrs)

    with :ok <- validate_dict_type(attrs[:dict_type]) do
      changeset = DictData.changeset(%DictData{}, attrs)
      changeset = Audit.put_actor(changeset, :creator_id, actor_id)

      case Repo.insert(changeset) do
        {:ok, dict_data} = result ->
          Cache.delete(dict_data_cache_key(dict_data.dict_type))
          result

        error ->
          error
      end
    end
  end

  @spec update_dict_data(integer() | String.t(), map(), keyword()) ::
          {:ok, DictData.t()} | {:error, term()}
  def update_dict_data(id, attrs, options)

  def update_dict_data(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:edit") do
      do_update_dict_data(id, attrs, Command.actor_id(options))
    end
  end

  def update_dict_data(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_dict_data(id, attrs, actor_id) do
    with {:ok, dict_data} <- get_dict_data(id) do
      old_dict_type = dict_data.dict_type
      attrs = normalize_attrs(attrs, @dict_data_attrs)

      with :ok <- validate_dict_type(attrs[:dict_type] || dict_data.dict_type) do
        changeset = DictData.changeset(dict_data, attrs)
        changeset = Audit.put_actor(changeset, :updater_id, actor_id)

        case Repo.update(changeset) do
          {:ok, updated} = result ->
            Cache.delete(dict_data_cache_key(old_dict_type))
            Cache.delete(dict_data_cache_key(updated.dict_type))
            result

          error ->
            error
        end
      end
    end
  end

  @spec delete_dict_data(integer() | String.t(), keyword()) :: :ok | {:error, term()}
  def delete_dict_data(id, options)

  def delete_dict_data(id, options) when is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:remove") do
      do_delete_dict_data(id)
    end
  end

  def delete_dict_data(_id, _options), do: {:error, :authorization_required}

  defp do_delete_dict_data(id) do
    with {:ok, dict_data} <- get_dict_data(id) do
      case Repo.update(Ecto.Changeset.change(dict_data, deleted: true)) do
        {:ok, _deleted} ->
          Cache.delete(dict_data_cache_key(dict_data.dict_type))
          :ok

        {:error, _changeset} ->
          {:error, :not_found}
      end
    end
  end

  @spec list_dict_types(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_dict_types(params \\ %{}) do
    query =
      from d in DictType,
        where: d.deleted == false,
        order_by: [desc: d.dict_id]

    query =
      query
      |> filter_contains(:dict_name, params["dictName"] || params[:dict_name])
      |> filter_contains(:dict_type, params["dictType"] || params[:dict_type])
      |> filter_status(params["status"] || params[:status])

    page_query(query, params, :dict_id, &dict_type_to_map/1)
  end

  @spec list_dict_data(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_dict_data(params \\ %{}) do
    query =
      from d in DictData,
        where: d.deleted == false,
        order_by: [asc: d.dict_sort, asc: d.dict_code]

    query =
      query
      |> filter_equal(:dict_type, params["dictType"] || params[:dict_type])
      |> filter_contains(:dict_label, params["dictLabel"] || params[:dict_label])
      |> filter_status(params["status"] || params[:status])

    page_query(query, params, :dict_code, &dict_data_to_map/1)
  end

  @spec list_dict_data_by_type(String.t()) :: [map()]
  def list_dict_data_by_type(dict_type) when is_binary(dict_type) do
    Cache.fetch(dict_data_cache_key(dict_type), @dict_data_cache_ttl, fn ->
      from(d in DictData,
        where: d.deleted == false and d.status == 1 and d.dict_type == ^dict_type,
        order_by: [asc: d.dict_sort, asc: d.dict_code]
      )
      |> Repo.all()
      |> Enum.map(&dict_data_to_map/1)
    end)
  end

  defp validate_dict_type(dict_type) when is_binary(dict_type) do
    case Repo.get_by(DictType, dict_type: dict_type, deleted: false, status: 1) do
      nil -> {:error, :dict_type_not_found}
      _dict_type -> :ok
    end
  end

  defp validate_dict_type(_dict_type), do: {:error, :dict_type_not_found}

  @doc "Clears all cached dictionary data values."
  @spec refresh_cache() :: :ok
  def refresh_cache, do: Cache.delete_prefix("keystone:dictionary:data:")

  def refresh_cache(options) when is_list(options) do
    with :ok <- Command.authorize(options, "system:dict:refresh") do
      refresh_cache()
    end
  end

  defp page_query(query, params, count_field, mapper) do
    Pagination.page(query, params, count_field, mapper)
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

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, value) do
    case Integer.parse(to_string(value)) do
      {status, ""} -> where(query, [record], record.status == ^status)
      _ -> query
    end
  end

  def dict_type_to_map(dict_type) do
    %{
      "dictId" => dict_type.dict_id,
      "dictName" => dict_type.dict_name,
      "dictType" => dict_type.dict_type,
      "status" => dict_type.status,
      "remark" => dict_type.remark,
      "createTime" => format_datetime(dict_type.create_time)
    }
  end

  def dict_data_to_map(dict_data) do
    %{
      "dictCode" => dict_data.dict_code,
      "dictType" => dict_data.dict_type,
      "dictLabel" => dict_data.dict_label,
      "dictValue" => dict_data.dict_value,
      "dictSort" => dict_data.dict_sort,
      "isDefault" => if(dict_data.is_default, do: 1, else: 0),
      "cssClass" => dict_data.css_class,
      "listClass" => dict_data.list_class,
      "status" => dict_data.status,
      "remark" => dict_data.remark,
      "createTime" => format_datetime(dict_data.create_time)
    }
  end

  defp dict_data_cache_key(dict_type), do: "keystone:dictionary:data:#{dict_type}"

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp normalize_attrs(attrs, fields) when is_map(attrs) do
    attrs =
      Enum.reduce(fields, %{}, fn {json_key, atom_key}, normalized ->
        cond do
          Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
          Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
          true -> normalized
        end
      end)

    normalize_default(attrs)
  end

  defp normalize_default(attrs) do
    case Map.fetch(attrs, :is_default) do
      {:ok, value} -> Map.put(attrs, :is_default, normalize_default_value(value))
      :error -> attrs
    end
  end

  defp normalize_default_value(value) when value in [true, 1, "1", "true", "TRUE"], do: true
  defp normalize_default_value(value) when value in [false, 0, "0", "false", "FALSE"], do: false
  defp normalize_default_value(value), do: value
end
