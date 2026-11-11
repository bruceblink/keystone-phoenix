# xlsxir 维护说明

本目录保留 `jsonkenl/xlsxir` 的提交 `91617449574273a59d3f8b2084e341f2bcb568a9`，用于兼容 Elixir 1.20。

仓库只维护三处编译兼容修正：移除未使用的 `Logger` 引用，并为 `ParseWorkbook` 的 struct 更新补充类型匹配。Excel 解析行为保持上游实现不变。升级依赖时，应先在全量编译和 Excel 导入测试中确认 warning 与行为变化。
