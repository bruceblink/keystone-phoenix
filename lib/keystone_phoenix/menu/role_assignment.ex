defmodule KeystonePhoenix.Menu.RoleAssignment do
  @moduledoc "菜单与角色绑定的命令边界。"

  import Ecto.Query

  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Authz.PolicyCache
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}

  @doc "按 Native API 的角色编码替换菜单绑定，并在事务成功后刷新策略缓存。"
  def replace(menu_id, role_codes, options) when is_list(role_codes) and is_list(options) do
    with :ok <- Command.authorize_resource(options, "menu:manage", :menu),
         {:ok, menu_id} <- Params.parse_uuid(menu_id),
         {:ok, role_ids} <- role_ids(role_codes) do
      Repo.transaction(fn ->
        ensure_menu!(menu_id)
        Repo.delete_all(from(rm in SysRoleMenu, where: rm.menu_id == ^menu_id))

        if role_ids != [] do
          Repo.insert_all(SysRoleMenu, Enum.map(role_ids, &%{role_id: &1, menu_id: menu_id}))
        end

        :ok
      end)
      |> case do
        {:ok, :ok} ->
          PolicyCache.invalidate()
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def replace(_menu_id, _role_codes, _options), do: {:error, :authorization_required}

  defp ensure_menu!(menu_id) do
    case Repo.get_by(SysMenu, menu_id: menu_id, deleted: false) do
      nil -> Repo.rollback(:not_found)
      _menu -> :ok
    end
  end

  defp role_ids(role_codes) do
    role_codes = role_codes |> Enum.map(&to_string/1) |> Enum.uniq()

    if Enum.any?(role_codes, &(&1 == "")) do
      {:error, :invalid_role_codes}
    else
      roles =
        from(role in SysRole,
          where: role.role_key in ^role_codes and role.deleted == false,
          select: {role.role_key, role.role_id}
        )
        |> Repo.all()

      role_map = Map.new(roles)

      if map_size(role_map) == length(role_codes) do
        {:ok, Enum.map(role_codes, &Map.fetch!(role_map, &1))}
      else
        {:error, :role_not_found}
      end
    end
  end
end
