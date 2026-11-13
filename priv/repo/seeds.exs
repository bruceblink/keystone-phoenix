if Mix.env() == :prod and System.get_env("ALLOW_PROD_SEEDS") not in ["true", "1"] do
  raise "production seeds are disabled; set ALLOW_PROD_SEEDS=true only for an explicit bootstrap"
end

alias KeystonePhoenix.Repo
alias KeystonePhoenix.Authz.PermissionCatalog
alias KeystonePhoenix.Authz.SysPermission
alias KeystonePhoenix.Authz.SysRolePermission
alias KeystonePhoenix.Authz.SysMenuPermission
alias KeystonePhoenix.Config.SysConfig
alias KeystonePhoenix.Department.SysDept
alias KeystonePhoenix.Dictionary.{DictData, DictType}
alias KeystonePhoenix.Menu.SysMenu
alias KeystonePhoenix.Notice.SysNotice
alias KeystonePhoenix.Post.SysPost
alias KeystonePhoenix.Role.SysRole
alias KeystonePhoenix.Role.SysRoleMenu
alias KeystonePhoenix.User.SysUser
alias KeystonePhoenix.Identity

import Ecto.Query

now = DateTime.utc_now()
namespace = Identity.permission_namespace()
root_dept_id = Identity.v5(namespace, "system:department:root")
headquarters_dept_id = Identity.v5(namespace, "system:department:headquarters")
engineering_dept_id = Identity.v5(namespace, "system:department:engineering")
market_dept_id = Identity.v5(namespace, "system:department:market")
admin_role_id = Identity.v5(namespace, "system:role:admin")
common_role_id = Identity.v5(namespace, "system:role:common")
admin_user_id = Identity.v5(namespace, "system:user:admin")
tester_user_id = Identity.v5(namespace, "system:user:tester")
operator_user_id = Identity.v5(namespace, "system:user:operator")
post_ceo_id = Identity.v5(namespace, "system:post:ceo")
post_engineer_id = Identity.v5(namespace, "system:post:engineer")
post_user_id = Identity.v5(namespace, "system:post:user")
menu_system_id = Identity.v5(namespace, "system:menu:system")
menu_user_id = Identity.v5(namespace, "system:menu:users")
menu_role_id = Identity.v5(namespace, "system:menu:roles")
menu_dept_id = Identity.v5(namespace, "system:menu:departments")
menu_post_id = Identity.v5(namespace, "system:menu:posts")
dict_yes_type_id = Identity.v5(namespace, "system:dictionary:common.yesOrNo")
dict_status_type_id = Identity.v5(namespace, "system:dictionary:common.status")
dict_yes_id = Identity.v5(namespace, "system:dictionary:common.yesOrNo:yes")
dict_no_id = Identity.v5(namespace, "system:dictionary:common.yesOrNo:no")
dict_enabled_id = Identity.v5(namespace, "system:dictionary:common.status:enabled")
dict_disabled_id = Identity.v5(namespace, "system:dictionary:common.status:disabled")
config_skin_id = Identity.v5(namespace, "system:config:sys.index.skinName")
config_password_id = Identity.v5(namespace, "system:config:sys.user.initPassword")
config_theme_id = Identity.v5(namespace, "system:config:sys.index.sideTheme")
config_captcha_id = Identity.v5(namespace, "system:config:sys.account.captchaOnOff")
config_register_id = Identity.v5(namespace, "system:config:sys.account.registerUser")
notice_dev_id = Identity.v5(namespace, "system:notice:development")
notice_maintenance_id = Identity.v5(namespace, "system:notice:maintenance")

dict_types = [
  %{
    dict_id: dict_yes_type_id,
    dict_name: "系统是否",
    dict_type: "common.yesOrNo",
    status: 1,
    remark: "系统是否列表",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    dict_id: dict_status_type_id,
    dict_name: "通用状态",
    dict_type: "common.status",
    status: 1,
    remark: "通用状态列表",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

Repo.insert_all(DictType, dict_types,
  on_conflict: :nothing,
  conflict_target: :dict_type
)

dict_data = [
  %{
    dict_code: dict_yes_id,
    dict_type: "common.yesOrNo",
    dict_label: "是",
    dict_value: 1,
    dict_sort: 1,
    is_default: false,
    list_class: "",
    status: 1,
    remark: "是",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    dict_code: dict_no_id,
    dict_type: "common.yesOrNo",
    dict_label: "否",
    dict_value: 0,
    dict_sort: 2,
    is_default: false,
    list_class: "danger",
    status: 1,
    remark: "否",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    dict_code: dict_enabled_id,
    dict_type: "common.status",
    dict_label: "正常",
    dict_value: 1,
    dict_sort: 1,
    is_default: false,
    list_class: "",
    status: 1,
    remark: "正常状态",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    dict_code: dict_disabled_id,
    dict_type: "common.status",
    dict_label: "停用",
    dict_value: 0,
    dict_sort: 2,
    is_default: false,
    list_class: "danger",
    status: 1,
    remark: "停用状态",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

Repo.insert_all(DictData, dict_data, on_conflict: :nothing, conflict_target: :dict_code)

config_entries = [
  %{
    config_id: config_skin_id,
    config_name: "主框架页-默认皮肤样式名称",
    config_key: "sys.index.skinName",
    config_options:
      Jason.encode!(["skin-blue", "skin-green", "skin-purple", "skin-red", "skin-yellow"]),
    config_value: "skin-blue",
    is_allow_change: true,
    remark: "蓝色 skin-blue、绿色 skin-green、紫色 skin-purple、红色 skin-red、黄色 skin-yellow",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    config_id: config_password_id,
    config_name: "用户管理-账号初始密码",
    config_key: "sys.user.initPassword",
    config_options: "",
    config_value: "123456",
    is_allow_change: true,
    remark: "初始化密码 123456",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    config_id: config_theme_id,
    config_name: "主框架页-侧边栏主题",
    config_key: "sys.index.sideTheme",
    config_options: Jason.encode!(["theme-dark", "theme-light"]),
    config_value: "theme-dark",
    is_allow_change: true,
    remark: "深色主题theme-dark，浅色主题theme-light",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    config_id: config_captcha_id,
    config_name: "账号自助-验证码开关",
    config_key: "sys.account.captchaOnOff",
    config_options: Jason.encode!(["true", "false"]),
    config_value: "false",
    is_allow_change: false,
    remark: "是否开启验证码功能（true开启，false关闭）",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    config_id: config_register_id,
    config_name: "账号自助-是否开启用户注册功能",
    config_key: "sys.account.registerUser",
    config_options: Jason.encode!(["true", "false"]),
    config_value: "true",
    is_allow_change: false,
    remark: "是否开启注册用户功能（true开启，false关闭）",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

Repo.insert_all(SysConfig, config_entries, on_conflict: :nothing, conflict_target: :config_key)

dept_entries = [
  %{
    dept_id: root_dept_id,
    parent_id: nil,
    ancestors: "",
    dept_name: "Keystone科技",
    order_num: 0,
    status: 1
  },
  %{
    dept_id: headquarters_dept_id,
    parent_id: root_dept_id,
    ancestors: root_dept_id,
    dept_name: "深圳总公司",
    order_num: 1,
    status: 1
  },
  %{
    dept_id: root_dept_id,
    parent_id: headquarters_dept_id,
    ancestors: Enum.join([root_dept_id, headquarters_dept_id], ","),
    dept_name: "研发部门",
    order_num: 1,
    status: 1
  },
  %{
    dept_id: market_dept_id,
    parent_id: headquarters_dept_id,
    ancestors: Enum.join([root_dept_id, headquarters_dept_id], ","),
    dept_name: "市场部门",
    order_num: 2,
    status: 1
  }
]

Repo.insert_all(
  SysDept,
  Enum.map(dept_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now})),
  on_conflict: :nothing,
  conflict_target: :dept_id
)

post_entries = [
  %{
    post_id: post_ceo_id,
    post_code: "ceo",
    post_name: "董事长",
    post_sort: 1,
    status: 1,
    remark: ""
  },
  %{
    post_id: post_engineer_id,
    post_code: "se",
    post_name: "项目经理",
    post_sort: 2,
    status: 1,
    remark: ""
  },
  %{
    post_id: post_user_id,
    post_code: "user",
    post_name: "普通员工",
    post_sort: 5,
    status: 0,
    remark: ""
  }
]

Repo.insert_all(
  SysPost,
  Enum.map(post_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now})),
  on_conflict: :nothing,
  conflict_target: :post_id
)

role_entries = [
  %{
    role_id: admin_role_id,
    role_name: "超级管理员",
    role_key: "admin",
    role_sort: 1,
    data_scope: 1,
    dept_id_set: "",
    status: 1,
    remark: "超级管理员"
  },
  %{
    role_id: common_role_id,
    role_name: "普通角色",
    role_key: "common",
    role_sort: 3,
    data_scope: 2,
    dept_id_set: "",
    status: 1,
    remark: "普通角色"
  }
]

Repo.insert_all(
  SysRole,
  Enum.map(role_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now})),
  on_conflict: :nothing,
  conflict_target: :role_id
)

menu_entries = [
  %{
    menu_id: menu_system_id,
    menu_name: "系统管理",
    menu_type: 2,
    router_name: "",
    parent_id: nil,
    path: "/system",
    is_button: false,
    permission: "",
    meta_info: Jason.encode!(%{"title" => "系统管理", "showParent" => true}),
    status: 1,
    remark: "系统管理目录"
  },
  %{
    menu_id: menu_user_id,
    menu_name: "用户管理",
    menu_type: 1,
    router_name: "SystemUser",
    parent_id: menu_system_id,
    path: "/system/user/index",
    is_button: false,
    # 菜单仅绑定目录中的新权限键，不负责创建权限。
    permission: "user:read",
    meta_info: Jason.encode!(%{"title" => "用户管理", "showParent" => true}),
    status: 1,
    remark: "用户管理菜单"
  },
  %{
    menu_id: menu_role_id,
    menu_name: "角色管理",
    menu_type: 1,
    router_name: "SystemRole",
    parent_id: menu_system_id,
    path: "/system/role/index",
    is_button: false,
    permission: "role:read",
    meta_info: Jason.encode!(%{"title" => "角色管理", "showParent" => true}),
    status: 1,
    remark: "角色管理菜单"
  },
  %{
    menu_id: menu_dept_id,
    menu_name: "部门管理",
    menu_type: 1,
    router_name: "Department",
    parent_id: menu_system_id,
    path: "/system/dept/index",
    is_button: false,
    permission: "department:read",
    meta_info: Jason.encode!(%{"title" => "部门管理", "showParent" => true}),
    status: 1,
    remark: "部门管理菜单"
  },
  %{
    menu_id: menu_post_id,
    menu_name: "岗位管理",
    menu_type: 1,
    router_name: "Post",
    parent_id: menu_system_id,
    path: "/system/post/index",
    is_button: false,
    permission: "post:read",
    meta_info: Jason.encode!(%{"title" => "岗位管理", "showParent" => true}),
    status: 1,
    remark: "岗位管理菜单"
  }
]

Repo.insert_all(
  SysMenu,
  Enum.map(menu_entries, fn entry ->
    entry
    |> Map.delete(:permission)
    |> Map.merge(%{deleted: false, create_time: now, update_time: now})
  end),
  on_conflict: :nothing,
  conflict_target: :menu_id
)

role_menu_entries =
  Enum.map(Enum.map(menu_entries, & &1.menu_id), &%{role_id: common_role_id, menu_id: &1})

Repo.insert_all(SysRoleMenu, role_menu_entries, on_conflict: :nothing)

permission_entries =
  PermissionCatalog.entries()
  |> Enum.map(fn entry ->
    entry
    |> Map.take([:permission, :resource, :domain, :action, :description, :risk, :deprecated])
    |> Map.put(:permission_id, entry.permission |> Identity.permission_id() |> Ecto.UUID.dump!())
    |> Map.put(:risk, Atom.to_string(entry.risk))
    |> Map.merge(%{status: 1, version: 1, create_time: now, update_time: now})
  end)

Repo.insert_all("sys_permission", permission_entries,
  on_conflict: :nothing,
  conflict_target: :permission
)

permission_ids =
  Repo.all(
    from permission in SysPermission, select: {permission.permission, permission.permission_id}
  )
  |> Map.new()

menu_permission_entries =
  Enum.flat_map(menu_entries, fn entry ->
    case Map.get(permission_ids, Map.get(entry, :permission, "")) do
      nil ->
        []

      permission_id ->
        [
          %{
            menu_id: entry.menu_id,
            permission_id: permission_id
          }
        ]
    end
  end)

Repo.insert_all(SysMenuPermission, menu_permission_entries, on_conflict: :nothing)

Repo.insert_all(
  SysRolePermission,
  Enum.map(Map.values(permission_ids), &%{role_id: common_role_id, permission_id: &1}),
  on_conflict: :nothing
)

Repo.insert_all(
  SysRolePermission,
  Enum.map(Map.values(permission_ids), &%{role_id: admin_role_id, permission_id: &1}),
  on_conflict: :nothing
)

notice_entries = [
  %{
    notice_id: notice_dev_id,
    notice_title: "Keystone Phoenix 开发环境",
    notice_type: 2,
    notice_content: "这是本地开发环境公告。",
    status: 1,
    remark: "管理员",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    notice_id: notice_maintenance_id,
    notice_title: "系统维护通知",
    notice_type: 1,
    notice_content: "请在维护窗口前保存工作。",
    status: 1,
    remark: "管理员",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

Repo.insert_all(SysNotice, notice_entries, on_conflict: :nothing, conflict_target: :notice_id)

user_entries = [
  %{
    user_id: admin_user_id,
    post_id: post_ceo_id,
    role_id: admin_role_id,
    dept_id: engineering_dept_id,
    username: "admin",
    nickname: "valarchie1",
    user_type: 0,
    email: "keystone@163.com",
    phone_number: "15888888883",
    sex: 0,
    avatar: "/profile/avatar/20230725164110_blob_6b7a989b1cdd4dd396665d2cfd2addc5.png",
    password: "$2b$12$i2O9Z9n1EJlcgy/rhwWHXudPrdLqOcFKMQ/yMq3WcF2X4c7LxH8OC",
    status: 1,
    login_ip: "127.0.0.1",
    login_date: now,
    remark: "管理员",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    user_id: tester_user_id,
    post_id: post_engineer_id,
    role_id: common_role_id,
    dept_id: market_dept_id,
    username: "ag1",
    nickname: "valarchie2",
    user_type: 0,
    email: "keystone1@qq.com",
    phone_number: "15666666666",
    sex: 1,
    avatar: "/profile/avatar/20230725114818_avatar_b5bf400732bb43369b4df58802049b22.png",
    password: "$2b$12$i2O9Z9n1EJlcgy/rhwWHXudPrdLqOcFKMQ/yMq3WcF2X4c7LxH8OC",
    status: 1,
    login_ip: "127.0.0.1",
    login_date: now,
    remark: "测试员1",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    user_id: operator_user_id,
    post_id: post_engineer_id,
    # 未分配角色使用 NULL，符合可选角色外键约束。
    role_id: nil,
    dept_id: market_dept_id,
    username: "ag2",
    nickname: "valarchie3",
    user_type: 0,
    email: "keystone2@qq.com",
    phone_number: "15666666667",
    sex: 1,
    avatar: "/profile/avatar/20230725114818_avatar_b5bf400732bb43369b4df58802049b22.png",
    password: "$2b$12$i2O9Z9n1EJlcgy/rhwWHXudPrdLqOcFKMQ/yMq3WcF2X4c7LxH8OC",
    status: 1,
    login_ip: "127.0.0.1",
    login_date: now,
    remark: "测试员2",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

Repo.insert_all(SysUser, user_entries, on_conflict: :nothing, conflict_target: :user_id)
