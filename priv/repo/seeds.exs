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
