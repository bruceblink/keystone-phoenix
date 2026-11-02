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
