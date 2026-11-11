if Mix.env() == :prod and System.get_env("ALLOW_PROD_SEEDS") not in ["true", "1"] do
  raise "production seeds are disabled; set ALLOW_PROD_SEEDS=true only for an explicit bootstrap"
end

alias KeystonePhoenix.Repo

now = DateTime.utc_now()

dict_types = [
  %{
    dict_name: "系统是否",
    dict_type: "common.yesOrNo",
    status: 1,
    remark: "系统是否列表",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    dict_name: "通用状态",
    dict_type: "common.status",
    status: 1,
    remark: "通用状态列表",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

Repo.insert_all("sys_dict_type", dict_types,
  on_conflict: :nothing,
  conflict_target: :dict_type
)

dict_data = [
  %{
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

if Repo.aggregate(KeystonePhoenix.Dictionary.DictData, :count, :dict_code) == 0 do
  Repo.insert_all("sys_dict_data", dict_data)
end

config_entries = [
  %{
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

if Repo.aggregate(KeystonePhoenix.Config.SysConfig, :count, :config_id) == 0 do
  Repo.insert_all("sys_config", config_entries)
end

dept_entries = [
  %{dept_id: 1, parent_id: 0, ancestors: "0", dept_name: "Keystone科技", order_num: 0, status: 1},
  %{dept_id: 2, parent_id: 1, ancestors: "0,1", dept_name: "深圳总公司", order_num: 1, status: 1},
  %{dept_id: 4, parent_id: 2, ancestors: "0,1,2", dept_name: "研发部门", order_num: 1, status: 1},
  %{dept_id: 5, parent_id: 2, ancestors: "0,1,2", dept_name: "市场部门", order_num: 2, status: 1}
]

if Repo.aggregate(KeystonePhoenix.Department.SysDept, :count, :dept_id) == 0 do
  Repo.insert_all(
    "sys_dept",
    Enum.map(dept_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now}))
  )

  Repo.query!("SELECT setval('sys_dept_dept_id_seq', (SELECT MAX(dept_id) FROM sys_dept))")
end

post_entries = [
  %{post_id: 1, post_code: "ceo", post_name: "董事长", post_sort: 1, status: 1, remark: ""},
  %{post_id: 2, post_code: "se", post_name: "项目经理", post_sort: 2, status: 1, remark: ""},
  %{post_id: 3, post_code: "user", post_name: "普通员工", post_sort: 5, status: 0, remark: ""}
]

if Repo.aggregate(KeystonePhoenix.Post.SysPost, :count, :post_id) == 0 do
  Repo.insert_all(
    "sys_post",
    Enum.map(post_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now}))
  )

  Repo.query!("SELECT setval('sys_post_post_id_seq', (SELECT MAX(post_id) FROM sys_post))")
end

role_entries = [
  %{
    role_id: 1,
    role_name: "超级管理员",
    role_key: "admin",
    role_sort: 1,
    data_scope: 1,
    dept_id_set: "",
    status: 1,
    remark: "超级管理员"
  },
  %{
    role_id: 2,
    role_name: "普通角色",
    role_key: "common",
    role_sort: 3,
    data_scope: 2,
    dept_id_set: "",
    status: 1,
    remark: "普通角色"
  }
]

if Repo.aggregate(KeystonePhoenix.Role.SysRole, :count, :role_id) == 0 do
  Repo.insert_all(
    "sys_role",
    Enum.map(role_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now}))
  )

  Repo.query!("SELECT setval('sys_role_role_id_seq', (SELECT MAX(role_id) FROM sys_role))")
end

menu_entries = [
  %{
    menu_id: 1,
    menu_name: "系统管理",
    menu_type: 2,
    router_name: "",
    parent_id: 0,
    path: "/system",
    is_button: false,
    permission: "",
    meta_info: Jason.encode!(%{"title" => "系统管理", "showParent" => true}),
    status: 1,
    remark: "系统管理目录"
  },
  %{
    menu_id: 5,
    menu_name: "用户管理",
    menu_type: 1,
    router_name: "SystemUser",
    parent_id: 1,
    path: "/system/user/index",
    is_button: false,
    permission: "system:user:list",
    meta_info: Jason.encode!(%{"title" => "用户管理", "showParent" => true}),
    status: 1,
    remark: "用户管理菜单"
  },
  %{
    menu_id: 6,
    menu_name: "角色管理",
    menu_type: 1,
    router_name: "SystemRole",
    parent_id: 1,
    path: "/system/role/index",
    is_button: false,
    permission: "system:role:list",
    meta_info: Jason.encode!(%{"title" => "角色管理", "showParent" => true}),
    status: 1,
    remark: "角色管理菜单"
  },
  %{
    menu_id: 8,
    menu_name: "部门管理",
    menu_type: 1,
    router_name: "Department",
    parent_id: 1,
    path: "/system/dept/index",
    is_button: false,
    permission: "system:dept:list",
    meta_info: Jason.encode!(%{"title" => "部门管理", "showParent" => true}),
    status: 1,
    remark: "部门管理菜单"
  },
  %{
    menu_id: 9,
    menu_name: "岗位管理",
    menu_type: 1,
    router_name: "Post",
    parent_id: 1,
    path: "/system/post/index",
    is_button: false,
    permission: "system:post:list",
    meta_info: Jason.encode!(%{"title" => "岗位管理", "showParent" => true}),
    status: 1,
    remark: "岗位管理菜单"
  }
]

if Repo.aggregate(KeystonePhoenix.Menu.SysMenu, :count, :menu_id) == 0 do
  Repo.insert_all(
    "sys_menu",
    Enum.map(menu_entries, &Map.merge(&1, %{deleted: false, create_time: now, update_time: now}))
  )

  Repo.query!("SELECT setval('sys_menu_menu_id_seq', (SELECT MAX(menu_id) FROM sys_menu))")
end

role_menu_entries = Enum.map(Enum.map(menu_entries, & &1.menu_id), &%{role_id: 2, menu_id: &1})

if Repo.aggregate(KeystonePhoenix.Role.SysRoleMenu, :count, :role_id) == 0 do
  Repo.insert_all("sys_role_menu", role_menu_entries)
end

notice_entries = [
  %{
    notice_id: 1,
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
    notice_id: 2,
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

if Repo.aggregate(KeystonePhoenix.Notice.SysNotice, :count, :notice_id) == 0 do
  Repo.insert_all("sys_notice", notice_entries)

  Repo.query!(
    "SELECT setval('sys_notice_notice_id_seq', (SELECT MAX(notice_id) FROM sys_notice))"
  )
end

user_entries = [
  %{
    user_id: 1,
    post_id: 1,
    role_id: 1,
    dept_id: 4,
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
    is_admin: true,
    remark: "管理员",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    user_id: 2,
    post_id: 2,
    role_id: 2,
    dept_id: 5,
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
    is_admin: false,
    remark: "测试员1",
    deleted: false,
    create_time: now,
    update_time: now
  },
  %{
    user_id: 3,
    post_id: 2,
    # 未分配角色使用 NULL，符合可选角色外键约束。
    role_id: nil,
    dept_id: 5,
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
    is_admin: false,
    remark: "测试员2",
    deleted: false,
    create_time: now,
    update_time: now
  }
]

if Repo.aggregate(KeystonePhoenix.User.SysUser, :count, :user_id) == 0 do
  Repo.insert_all("sys_user", user_entries)
  Repo.query!("SELECT setval('sys_user_user_id_seq', (SELECT MAX(user_id) FROM sys_user))")
end
