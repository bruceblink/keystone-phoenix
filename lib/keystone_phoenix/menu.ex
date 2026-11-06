defmodule KeystonePhoenix.Menu do
  @moduledoc "Query boundary for menu and permission management."

  import Ecto.Query

  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Tree

  @menu_attrs [
    {"menuName", :menu_name},
    {"menuType", :menu_type},
    {"routerName", :router_name},
    {"parentId", :parent_id},
    {"path", :path},
    {"isButton", :is_button},
    {"permission", :permission},
    {"metaInfo", :meta_info},
    {"meta", :meta_info},
    {"status", :status},
    {"remark", :remark}
  ]

  def list_menus(params \\ %{}) do
    query =
      from(m in SysMenu,
        where: m.deleted == false,
        order_by: [asc: m.parent_id, asc: m.menu_id]
      )

    query = filter_status(query, params["status"] || params[:status])
    query = filter_type(query, params["menuType"] || params[:menu_type])
    Repo.all(query) |> Enum.map(&menu_to_map/1)
  end

  def list_dropdown do
    list_menus(%{"status" => 1})
  end

  def get_menu(id) do
    case Repo.get_by(SysMenu, menu_id: id, deleted: false) do
      nil -> {:error, :not_found}
      menu -> {:ok, menu}
    end
  end

  def create_menu(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, parent_id} <- parent_id(attrs[:parent_id]),
         :ok <- ensure_parent(parent_id),
         :ok <- ensure_name_available(attrs[:menu_name], parent_id, nil),
         :ok <- validate_menu_rules(attrs, parent_id, nil) do
      attrs = Map.put(attrs, :parent_id, parent_id)
      Repo.insert(SysMenu.changeset(%SysMenu{}, attrs))
    end
  end

  def create_menu(_attrs), do: {:error, invalid_changeset(:menu_name)}

  def update_menu(id, attrs) when is_map(attrs) do
    with {:ok, menu} <- get_menu(id) do
      attrs = normalize_attrs(attrs)

      with {:ok, parent_id} <- parent_id(Map.get(attrs, :parent_id, menu.parent_id)) do
        with :ok <- ensure_not_descendant(menu.menu_id, parent_id),
             :ok <- ensure_parent(parent_id),
             :ok <-
               ensure_name_available(attrs[:menu_name] || menu.menu_name, parent_id, menu.menu_id),
             :ok <- validate_menu_rules(attrs, parent_id, menu) do
          Repo.update(SysMenu.changeset(menu, Map.put(attrs, :parent_id, parent_id)))
        end
      end
    end
  end

  def update_menu(_id, _attrs), do: {:error, invalid_changeset(:menu_name)}

  def delete_menu(id) do
    with {:ok, menu} <- get_menu(id) do
      cond do
        child_count(menu.menu_id) > 0 ->
          {:error, :has_children}

        assigned_to_role?(menu.menu_id) ->
          {:error, :assigned_to_role}

        true ->
          case Repo.update(Ecto.Changeset.change(menu, deleted: true)) do
            {:ok, _deleted} -> :ok
            {:error, changeset} -> {:error, changeset}
          end
      end
    end
  end

  def menus_for_user(user) do
    query =
      from(m in SysMenu,
        join: rm in "sys_role_menu",
        on: rm.menu_id == m.menu_id,
        join: role in "sys_role",
        on: role.role_id == rm.role_id,
        where:
          m.deleted == false and m.status == 1 and role.deleted == false and role.status == 1 and
            rm.role_id == ^user.role_id,
        order_by: [asc: m.parent_id, asc: m.menu_id],
        distinct: true
      )

    if user.is_admin do
      list_menus(%{"status" => 1})
    else
      Repo.all(query) |> Enum.map(&menu_to_map/1)
    end
  end

  @doc "Returns the button and route permission strings for an authenticated user."
  @spec permissions_for_user(map()) :: [String.t()]
  def permissions_for_user(%{is_admin: true}), do: ["*:*:*"]

  def permissions_for_user(%{"isAdmin" => 1}), do: ["*:*:*"]

  def permissions_for_user(user) do
    menus_for_user(user)
    |> Enum.map(&Map.get(&1, "permission"))
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.uniq()
  end

  @doc "Builds the authenticated user's router tree."
  def routers_for_user(user) do
    menus_for_user(user)
    |> Enum.reject(&(&1["isButton"] == 1))
    |> build_tree()
  end

  def menu_to_map(menu) do
    %{
      "menuId" => menu.menu_id,
      "menuName" => menu.menu_name,
      "menuType" => menu.menu_type,
      "routerName" => menu.router_name,
      "parentId" => menu.parent_id,
      "path" => menu.path,
      "isButton" => if(menu.is_button, do: 1, else: 0),
      "permission" => menu.permission,
      "meta" => decode_meta(menu.meta_info),
      "status" => menu.status,
      "remark" => menu.remark,
      "createTime" => format_datetime(menu.create_time)
    }
  end

  defp normalize_attrs(attrs) do
    attrs =
      Enum.reduce(@menu_attrs, %{}, fn {json_key, atom_key}, normalized ->
        cond do
          Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
          Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
          true -> normalized
        end
      end)

    normalize_meta(attrs)
  end

  defp normalize_meta(attrs) do
    case Map.fetch(attrs, :meta_info) do
      {:ok, meta} when is_map(meta) -> Map.put(attrs, :meta_info, Jason.encode!(meta))
      {:ok, nil} -> Map.put(attrs, :meta_info, "{}")
      _ -> attrs
    end
  end

  defp parent_id(nil), do: {:ok, 0}

  defp parent_id(value) do
    case Params.non_negative_integer(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_parent}
    end
  end

  defp ensure_parent(0), do: :ok

  defp ensure_parent(id) do
    case get_menu(id) do
      {:ok, _parent} -> :ok
      {:error, :not_found} -> {:error, :parent_not_found}
    end
  end

  defp ensure_not_descendant(menu_id, parent_id) when menu_id == parent_id,
    do: {:error, :invalid_parent}

  defp ensure_not_descendant(_menu_id, 0), do: :ok

  defp ensure_not_descendant(menu_id, parent_id) do
    if parent_chain_contains?(parent_id, menu_id, MapSet.new()),
      do: {:error, :invalid_parent},
      else: :ok
  end

  defp parent_chain_contains?(current_id, target_id, visited) do
    cond do
      current_id == target_id ->
        true

      MapSet.member?(visited, current_id) ->
        true

      true ->
        case get_menu(current_id) do
          {:ok, %{parent_id: 0}} ->
            false

          {:ok, parent} ->
            parent_chain_contains?(parent.parent_id, target_id, MapSet.put(visited, current_id))

          {:error, :not_found} ->
            false
        end
    end
  end

  defp ensure_name_available(nil, _parent_id, _menu_id), do: :ok

  defp ensure_name_available(name, parent_id, menu_id) do
    query =
      from m in SysMenu,
        where: m.deleted == false and m.parent_id == ^parent_id and m.menu_name == ^name

    query = if menu_id, do: where(query, [menu], menu.menu_id != ^menu_id), else: query
    if Repo.exists?(query), do: {:error, :name_exists}, else: :ok
  end

  defp validate_menu_rules(attrs, parent_id, current_menu) do
    menu_type = menu_type_value(attrs, current_menu)
    is_button = boolean_value(Map.get(attrs, :is_button, current_menu && current_menu.is_button))

    with :ok <- validate_type_change(current_menu, menu_type),
         :ok <- validate_parent_type(parent_id, is_button),
         :ok <-
           validate_external_link(
             menu_type,
             Map.get(attrs, :path, current_menu && current_menu.path)
           ) do
      :ok
    end
  end

  defp menu_type_value(attrs, current_menu) do
    value = Map.get(attrs, :menu_type, current_menu && current_menu.menu_type)

    case Params.parse_integer(value) do
      {:ok, menu_type} -> menu_type
      :error -> value
    end
  end

  defp validate_type_change(nil, _menu_type), do: :ok

  defp validate_type_change(%{is_button: false, menu_type: current_type}, menu_type)
       when is_integer(menu_type) and menu_type != current_type,
       do: {:error, :menu_type_locked}

  defp validate_type_change(_current_menu, _menu_type), do: :ok

  defp validate_parent_type(0, _is_button), do: :ok

  defp validate_parent_type(parent_id, is_button) do
    case get_menu(parent_id) do
      {:ok, %{menu_type: parent_type}} when is_button and parent_type in [3, 4] ->
        {:error, :button_parent_invalid}

      {:ok, %{menu_type: parent_type}} when not is_button and parent_type != 2 ->
        {:error, :menu_parent_invalid}

      {:ok, _parent} ->
        :ok

      {:error, :not_found} ->
        {:error, :parent_not_found}
    end
  end

  defp validate_external_link(4, path) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> :ok
      _ -> {:error, :external_link_invalid}
    end
  end

  defp validate_external_link(4, _path), do: {:error, :external_link_invalid}
  defp validate_external_link(_menu_type, _path), do: :ok

  defp boolean_value(value) when value in [true, 1, "true", "1"], do: true
  defp boolean_value(_value), do: false

  defp child_count(parent_id) do
    from(menu in SysMenu, where: menu.parent_id == ^parent_id and menu.deleted == false)
    |> Repo.aggregate(:count, :menu_id)
  end

  defp assigned_to_role?(menu_id) do
    Repo.exists?(from role_menu in "sys_role_menu", where: role_menu.menu_id == ^menu_id)
  end

  defp invalid_changeset(field),
    do: Ecto.Changeset.add_error(Ecto.Changeset.change(%SysMenu{}), field, "参数无效")

  defp build_tree(menus) do
    Tree.nest(menus, "parentId", "menuId")
  end

  defp filter_status(query, value) do
    case Params.parse_integer(value) do
      {:ok, status} -> where(query, [menu], menu.status == ^status)
      :error -> query
    end
  end

  defp filter_type(query, value) do
    case Params.parse_integer(value) do
      {:ok, menu_type} -> where(query, [menu], menu.menu_type == ^menu_type)
      :error -> query
    end
  end

  defp decode_meta(meta_info) when is_binary(meta_info) do
    case Jason.decode(meta_info) do
      {:ok, meta} -> meta
      _ -> %{}
    end
  end

  defp decode_meta(_meta_info), do: %{}

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
