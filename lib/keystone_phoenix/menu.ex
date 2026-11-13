defmodule KeystonePhoenix.Menu do
  @moduledoc "Query boundary for menu and permission management."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Authz.SysPermission
  alias KeystonePhoenix.Authz.PolicyCache
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
    query = filter_button(query, params["isButton"] || params[:is_button])
    Repo.all(query) |> Enum.map(&menu_to_map/1)
  end

  def list_dropdown do
    list_menus(%{"status" => 1})
  end

  def get_menu(id) do
    case Params.parse_uuid(id) do
      {:ok, id} ->
        case Repo.get_by(SysMenu, menu_id: id, deleted: false) do
          nil -> {:error, :not_found}
          menu -> {:ok, menu}
        end

      :error ->
        {:error, :not_found}
    end
  end

  def create_menu(attrs, options)

  def create_menu(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Command.authorize(options, "menu:create") do
      do_create_menu(attrs, Command.actor_id(options))
    end
  end

  def create_menu(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_menu(attrs, actor_id) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, parent_id} <- parent_id(attrs[:parent_id]),
         :ok <- ensure_parent(parent_id),
         :ok <- ensure_name_available(attrs[:menu_name], parent_id, nil),
         :ok <- validate_menu_rules(attrs, parent_id, nil) do
      attrs = Map.put(attrs, :parent_id, parent_id)

      with {:ok, permission_id} <- permission_id(attrs[:permission]) do
        attrs
        |> Map.delete(:permission)
        |> then(&SysMenu.changeset(%SysMenu{}, &1))
        |> Audit.put_actor(:creator_id, actor_id)
        |> Repo.insert()
        |> persist_menu_permission(permission_id)
        |> invalidate_policy_cache()
      end
    end
  end

  def update_menu(id, attrs, options)

  def update_menu(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Command.authorize(options, "menu:update") do
      do_update_menu(id, attrs, Command.actor_id(options))
    end
  end

  def update_menu(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_menu(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, menu} <- get_menu(id) do
      attrs = normalize_attrs(attrs)

      with {:ok, parent_id} <- parent_id(Map.get(attrs, :parent_id, menu.parent_id)) do
        with :ok <- ensure_not_descendant(menu.menu_id, parent_id),
             :ok <- ensure_parent(parent_id),
             :ok <-
               ensure_name_available(attrs[:menu_name] || menu.menu_name, parent_id, menu.menu_id),
             :ok <- validate_menu_rules(attrs, parent_id, menu) do
          with {:ok, permission_id} <-
                 permission_id(Map.get(attrs, :permission, permission_for_menu(menu.menu_id))) do
            menu
            |> SysMenu.changeset(Map.put(attrs, :parent_id, parent_id) |> Map.delete(:permission))
            |> Audit.put_actor(:updater_id, actor_id)
            |> Repo.update()
            |> persist_menu_permission(permission_id)
            |> invalidate_policy_cache()
          end
        end
      end
    end
  end

  def delete_menu(id, options) when is_list(options) do
    with :ok <- Command.authorize(options, "menu:delete") do
      do_delete_menu(id, Command.actor_id(options))
    end
  end

  def delete_menu(_id, _options), do: {:error, :authorization_required}

  defp do_delete_menu(id, actor_id) do
    with {:ok, menu} <- get_menu(id) do
      cond do
        child_count(menu.menu_id) > 0 ->
          {:error, :has_children}

        assigned_to_role?(menu.menu_id) ->
          {:error, :assigned_to_role}

        true ->
          changeset = Ecto.Changeset.change(menu, deleted: true)
          changeset = Audit.put_actor(changeset, :updater_id, actor_id)

          case Repo.update(changeset) do
            {:ok, _deleted} ->
              PolicyCache.invalidate()
              :ok

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end
  end

  def menus_for_user(%{role_id: nil}), do: []
  def menus_for_user(%{"roleId" => nil}), do: []

  def menus_for_user(user) do
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
    |> Repo.all()
    |> Enum.map(&menu_to_map/1)
  end

  @doc "Returns the button and route permission strings for an authenticated user."
  @spec permissions_for_user(map()) :: [String.t()]
  def permissions_for_user(%{role_id: nil}), do: []
  def permissions_for_user(%{"roleId" => nil}), do: []

  def permissions_for_user(user) do
    role_id = Map.get(user, :role_id, Map.get(user, "roleId"))

    from(role_permission in "sys_role_permission",
      join: permission in SysPermission,
      on: permission.permission_id == role_permission.permission_id,
      join: role in "sys_role",
      on: role.role_id == role_permission.role_id,
      where:
        role_permission.role_id == ^role_id and role.deleted == false and role.status == 1 and
          permission.status == 1 and permission.deprecated == false,
      select: permission.permission,
      order_by: permission.permission
    )
    |> Repo.all()
  end

  @doc "Builds the authenticated user's router tree."
  def routers_for_user(user) do
    menus_for_user(user)
    |> Enum.reject(& &1["isButton"])
    |> build_tree()
  end

  def menu_to_map(menu) do
    meta = decode_meta(menu.meta_info)
    menu_type = if menu.is_button, do: 0, else: menu.menu_type

    %{
      "menuId" => menu.menu_id,
      "id" => menu.menu_id,
      "menuName" => menu.menu_name,
      "menuType" => menu_type,
      "menuTypeStr" => menu_type_label(menu_type, menu.is_button),
      "routerName" => menu.router_name,
      "parentId" => menu.parent_id,
      "path" => menu.path,
      "isButton" => menu.is_button,
      "permission" => permission_for_menu(menu.menu_id),
      "meta" => meta,
      "rank" => Map.get(meta, "rank"),
      "icon" => Map.get(meta, "icon"),
      "status" => menu.status,
      "statusStr" => status_label(menu.status),
      "remark" => menu.remark,
      "createTime" => format_datetime(menu.create_time)
    }
  end

  defp permission_id(nil), do: {:ok, nil}

  defp permission_id(permission) when is_binary(permission) do
    case Repo.get_by(SysPermission,
           permission: String.trim(permission),
           status: 1,
           deprecated: false
         ) do
      nil -> {:error, :permission_not_found}
      entry -> {:ok, entry.permission_id}
    end
  end

  defp permission_id(_permission), do: {:error, :permission_not_found}

  defp permission_for_menu(menu_id) do
    Repo.one(
      from menu_permission in "sys_menu_permission",
        join: permission in SysPermission,
        on: permission.permission_id == menu_permission.permission_id,
        where: menu_permission.menu_id == ^menu_id and permission.status == 1,
        select: permission.permission
    )
  end

  defp persist_menu_permission({:ok, menu}, nil) do
    Repo.delete_all(from link in "sys_menu_permission", where: link.menu_id == ^menu.menu_id)
    {:ok, menu}
  end

  defp persist_menu_permission({:ok, menu}, permission_id) do
    Repo.delete_all(from link in "sys_menu_permission", where: link.menu_id == ^menu.menu_id)

    Repo.insert_all(
      "sys_menu_permission",
      [%{menu_id: menu.menu_id, permission_id: permission_id}],
      on_conflict: :nothing
    )

    {:ok, menu}
  end

  defp persist_menu_permission(error, _permission_id), do: error

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

  defp parent_id(nil), do: {:ok, nil}

  defp parent_id(value) do
    case Params.parse_uuid(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_parent}
    end
  end

  defp ensure_parent(nil), do: :ok

  defp ensure_parent(id) do
    case get_menu(id) do
      {:ok, _parent} -> :ok
      {:error, :not_found} -> {:error, :parent_not_found}
    end
  end

  defp ensure_not_descendant(menu_id, parent_id) when menu_id == parent_id,
    do: {:error, :invalid_parent}

  defp ensure_not_descendant(_menu_id, nil), do: :ok

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
          {:ok, %{parent_id: nil}} ->
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

  defp validate_parent_type(nil, _is_button), do: :ok

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
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if String.contains?(path, ["\r", "\n"]), do: {:error, :external_link_invalid}, else: :ok

      _ ->
        {:error, :external_link_invalid}
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

  defp invalidate_policy_cache({:ok, _value} = result) do
    PolicyCache.invalidate()
    result
  end

  defp invalidate_policy_cache(result), do: result

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

  defp filter_button(query, value) when value in [true, false],
    do: where(query, [menu], menu.is_button == ^value)

  defp filter_button(query, value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> where(query, [menu], menu.is_button == true)
      "false" -> where(query, [menu], menu.is_button == false)
      "1" -> where(query, [menu], menu.is_button == true)
      "0" -> where(query, [menu], menu.is_button == false)
      _ -> query
    end
  end

  defp filter_button(query, _value), do: query

  defp menu_type_label(_menu_type, true), do: "按钮"
  defp menu_type_label(1, false), do: "页面"
  defp menu_type_label(2, false), do: "目录"
  defp menu_type_label(3, false), do: "内嵌Iframe"
  defp menu_type_label(4, false), do: "外链跳转"
  defp menu_type_label(_menu_type, false), do: "权限"

  defp status_label(1), do: "正常"
  defp status_label(0), do: "停用"
  defp status_label(status), do: to_string(status || "")

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
