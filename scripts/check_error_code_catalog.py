#!/usr/bin/env python3
"""静态检查三个仓库的业务错误码目录，不启动应用或外部服务。"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# 这里保存跨项目必须一致的代码和默认 HTTP 状态，避免单个实现文件悄悄扩展集合。
EXPECTED_STATUS = {
    "authentication_required": 401,
    "invalid_credential": 401,
    "mfa_required": 401,
    "mfa_invalid_code": 401,
    "mfa_step_up_required": 403,
    "mfa_state_conflict": 409,
    "mfa_challenge_invalid": 401,
    "active_session_conflict": 409,
    "permission_denied": 403,
    "data_scope_denied": 403,
    "session_revoked": 401,
    "resource_not_found": 404,
    "resource_conflict": 409,
    "rate_limited": 429,
    "precondition_required": 428,
    "payload_too_large": 413,
    "https_required": 426,
    "validation_failed": 422,
    "service_unavailable": 503,
    "authorization_unavailable": 503,
    "internal_error": 500,
}


def read_text(path: Path, errors: list[str]) -> str:
    """读取 UTF-8 源文件；缺失或无法读取时记录明确错误。"""
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"无法读取 {path}: {exc}")
        return ""


def parse_catalog_document(path: Path, errors: list[str]) -> dict[str, int]:
    """解析主目录表格，确认文档本身没有遗漏或重复代码。"""
    text = read_text(path, errors)
    section = re.search(r"^## 规范服务端错误码\s*$([\s\S]*?)(?=^## |\Z)", text, re.MULTILINE)
    if not section:
        errors.append(f"主目录缺少“规范服务端错误码”表格: {path}")
        return {}

    rows: list[tuple[str, int]] = []
    for line in section.group(1).splitlines():
        match = re.match(r"\|\s*`([a-z][a-z0-9_]*)`\s*\|\s*(\d{3})\s*\|", line)
        if match:
            rows.append((match.group(1), int(match.group(2))))

    codes = [code for code, _ in rows]
    duplicates = sorted({code for code in codes if codes.count(code) > 1})
    if duplicates:
        errors.append(f"主目录存在重复代码: {', '.join(duplicates)}")
    return dict(rows)


def parse_phoenix(path: Path, errors: list[str]) -> tuple[list[str], dict[str, int]]:
    """从 Elixir ErrorCatalog 的 @entries 中提取代码和状态。"""
    text = read_text(path, errors)
    entries_match = re.search(r"@entries\s+%\{([\s\S]*?)\n\s*\}\n\s*@doc", text)
    if not entries_match:
        errors.append(f"Phoenix 缺少 ErrorCatalog.@entries: {path}")
        return [], {}

    body = entries_match.group(1)
    matches = list(re.finditer(r'^\s*"([a-z][a-z0-9_]*)"\s*=>\s*%\{', body, re.MULTILINE))
    codes: list[str] = []
    statuses: dict[str, int] = {}
    for index, match in enumerate(matches):
        code = match.group(1)
        codes.append(code)
        end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        entry = body[match.start() : end]
        status = re.search(r"\bstatus:\s*(\d+)", entry)
        if not status:
            errors.append(f"Phoenix 目录项缺少 status: {code}")
        else:
            statuses[code] = int(status.group(1))

    for required in ("def metadata", "def valid?"):
        if required not in text:
            errors.append(f"Phoenix 缺少代码反查入口 {required}: {path}")
    return codes, statuses


def parse_native(path: Path, errors: list[str]) -> tuple[list[str], dict[str, int]]:
    """从 Java ErrorCode 枚举构造代码到状态的静态映射。"""
    text = read_text(path, errors)
    rows = re.findall(r'^\s*[A-Z][A-Z0-9_]*\("([a-z][a-z0-9_]*)",\s*(\d+),', text, re.MULTILINE)
    codes = [code for code, _ in rows]
    statuses = {code: int(status) for code, status in rows}
    if "static ErrorCode fromCode" not in text:
        errors.append(f"Native 缺少代码反查入口 fromCode: {path}")
    if "static boolean isRegistered" not in text:
        errors.append(f"Native 缺少代码反查入口 isRegistered: {path}")
    return codes, statuses


def extract_ts_array(text: str, name: str, errors: list[str]) -> list[str]:
    """提取 TypeScript 的 `as const` 字符串数组，并保留重复项供检查。"""
    match = re.search(rf"export const {name}\s*=\s*\[([\s\S]*?)\]\s*as const", text)
    if not match:
        errors.append(f"admin-web 缺少数组 {name}")
        return []
    return re.findall(r"'([a-z][a-z0-9_]*)'", match.group(1))


def parse_admin(path: Path, errors: list[str]) -> tuple[list[str], dict[str, int], set[str]]:
    """提取 admin-web 的服务端集合、目录状态和安全提示映射。"""
    text = read_text(path, errors)
    codes = extract_ts_array(text, "SERVER_ERROR_CODES", errors)
    client_codes = set(extract_ts_array(text, "CLIENT_ERROR_CODES", errors))

    catalog_block = re.search(
        r"export const BUSINESS_ERROR_CATALOG[^=]*=\s*\{([\s\S]*?)\n\}", text
    )
    statuses: dict[str, int] = {}
    if not catalog_block:
        errors.append("admin-web 缺少 BUSINESS_ERROR_CATALOG")
    else:
        for code, status in re.findall(
            r"^\s*([a-z][a-z0-9_]*)\s*:\s*\{\s*httpStatus:\s*(\d+)",
            catalog_block.group(1),
            re.MULTILINE,
        ):
            statuses[code] = int(status)

    messages_block = re.search(
        r"const errorMessages:\s*Record<string, string>\s*=\s*\{([\s\S]*?)\n\}", text
    )
    message_codes = set()
    if not messages_block:
        errors.append("admin-web 缺少 errorMessages")
    else:
        message_codes = set(re.findall(r"\b([a-z][a-z0-9_]*)\s*:", messages_block.group(1)))

    if "getBusinessErrorDefinition" not in text:
        errors.append("admin-web 缺少代码反查入口 getBusinessErrorDefinition")
    if "class ApiError" not in text:
        errors.append("admin-web 缺少 ApiError")
    missing_messages = sorted(set(EXPECTED_STATUS) - message_codes)
    if missing_messages:
        errors.append(f"admin-web 可读提示缺少规范代码: {', '.join(missing_messages)}")
    return codes, statuses, client_codes


def check_code_set(name: str, codes: list[str], errors: list[str]) -> None:
    """检查实现中的代码唯一且与跨项目集合完全相同。"""
    duplicates = sorted({code for code in codes if codes.count(code) > 1})
    if duplicates:
        errors.append(f"{name} 存在重复代码: {', '.join(duplicates)}")
    actual = set(codes)
    expected = set(EXPECTED_STATUS)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        errors.append(f"{name} 缺少规范代码: {', '.join(missing)}")
    if extra:
        errors.append(f"{name} 含未登记代码: {', '.join(extra)}")


def check_statuses(name: str, statuses: dict[str, int], errors: list[str]) -> None:
    """检查实现记录的默认 HTTP 状态与主目录一致。"""
    for code, expected in EXPECTED_STATUS.items():
        actual = statuses.get(code)
        if actual != expected:
            errors.append(f"{name} 的 {code} 状态为 {actual!r}，目录要求 {expected}")


def main() -> int:
    parser = argparse.ArgumentParser(description="静态检查 Keystone 跨项目业务错误码目录")
    parser.add_argument("--phoenix-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--native-root", type=Path, default=None)
    parser.add_argument("--admin-root", type=Path, default=None)
    args = parser.parse_args()

    phoenix_root = args.phoenix_root.resolve()
    native_root = (args.native_root or phoenix_root.parent / "keystone-native").resolve()
    admin_root = (args.admin_root or phoenix_root.parent / "keystone-admin-web").resolve()
    errors: list[str] = []

    document = parse_catalog_document(phoenix_root / "docs/11-business-error-code-catalog.md", errors)
    if document != EXPECTED_STATUS:
        missing = sorted(set(EXPECTED_STATUS) - set(document))
        extra = sorted(set(document) - set(EXPECTED_STATUS))
        if missing:
            errors.append(f"主目录缺少代码: {', '.join(missing)}")
        if extra:
            errors.append(f"主目录含未登记代码: {', '.join(extra)}")
        for code in sorted(set(document) & set(EXPECTED_STATUS)):
            if document[code] != EXPECTED_STATUS[code]:
                errors.append(
                    f"主目录的 {code} 状态为 {document[code]}，目录基线要求 {EXPECTED_STATUS[code]}"
                )

    phoenix_codes, phoenix_statuses = parse_phoenix(
        phoenix_root / "lib/keystone_phoenix_web/error_catalog.ex", errors
    )
    native_codes, native_statuses = parse_native(
        native_root / "src/main/java/app/keystone/ErrorCode.java", errors
    )
    admin_codes, admin_statuses, client_codes = parse_admin(
        admin_root / "src/shared/api/errors.ts", errors
    )

    check_code_set("Phoenix", phoenix_codes, errors)
    check_code_set("Native", native_codes, errors)
    check_code_set("admin-web", admin_codes, errors)
    check_statuses("Phoenix", phoenix_statuses, errors)
    check_statuses("Native", native_statuses, errors)
    check_statuses("admin-web", admin_statuses, errors)
    overlap = sorted(client_codes & set(EXPECTED_STATUS))
    if overlap:
        errors.append(f"admin-web 客户端本地代码混入服务端集合: {', '.join(overlap)}")
    if len(client_codes) != len(extract_ts_array(read_text(admin_root / "src/shared/api/errors.ts", errors), "CLIENT_ERROR_CODES", errors)):
        errors.append("admin-web CLIENT_ERROR_CODES 存在重复代码")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"OK: {len(EXPECTED_STATUS)} canonical server error codes; Phoenix, Native and admin-web are aligned")
    print(f"OK: {len(client_codes)} client-local error codes remain separate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
