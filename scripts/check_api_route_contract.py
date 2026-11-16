#!/usr/bin/env python3
"""核对 admin-web 调用入口与 Native/Phoenix 的 HTTP 路由集合。"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


HTTP_METHODS = "GET|POST|PUT|PATCH|DELETE"
LEGACY_PATH_MARKERS = (
    "/system/",
    "/logs/",
    "/auth/passkey",
    "/health/ready",
    "/monitor/networkStatus",
    "/users/import/template",
    "/run",
)


@dataclass(frozen=True)
class Route:
    method: str
    path: str
    source: str


def normalize_path(path: str) -> str:
    """统一斜杠、路径参数和末尾斜杠，保留方法和资源层级。"""
    path = re.sub(r"/+", "/", path)
    path = re.sub(r":([A-Za-z_][\w]*|\{[^}]+\})", ":param", path)
    path = re.sub(r"\{[^}]+\}", ":param", path)
    return path.rstrip("/") or "/"


def read(path: Path) -> str:
    """读取 UTF-8 源文件；调用方统一处理路径错误。"""
    return path.read_text(encoding="utf-8")


def call_end(text: str, start: int) -> int:
    """找到 request 调用的右括号，跳过字符串和模板字面量内容。"""
    depth = 0
    quote: str | None = None
    index = start

    while index < len(text):
        char = text[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
        elif char in "'\"`":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1

    return len(text)


def parse_admin(root: Path) -> list[Route]:
    """从 admin-web 的真实请求封装提取方法和路径。"""
    files = (
        root / "src/shared/api/client.ts",
        root / "src/shared/api/jobClient.ts",
        root / "src/shared/api/userFileClient.ts",
    )
    text = "\n".join(read(path) for path in files)
    pattern = re.compile(r"\b(?:request|requestFile)\s*(?:<[^>]+>)?\s*\(")
    routes: list[Route] = []

    for match in pattern.finditer(text):
        opening = text.find("(", match.start(), match.end())
        ending = call_end(text, opening)
        call = text[opening + 1 : ending]
        path_match = re.match(
            r"\s*(?:(['\"])(/[^'\"]*)\1|`([^`]+)`)", call, re.DOTALL
        )
        if not path_match:
            continue

        path = path_match.group(2) or path_match.group(3) or ""
        path = path.split("${query")[0]
        path = re.sub(r"\$\{[^}]*?encodeURIComponent\([^)]*\)[^}]*\}", ":param", path)
        path = re.sub(r"\$\{[^}]+\}", ":param", path)
        path = path.split("?")[0]
        if not path.startswith("/"):
            continue

        method_match = re.search(r"\bmethod\s*:\s*['\"](" + HTTP_METHODS + r")", call)
        method = method_match.group(1) if method_match else "GET"
        routes.append(Route(method, normalize_path("/api/v1" + path), "admin-web"))

    return routes


def parse_native(root: Path) -> list[Route]:
    """从 JAX-RS 类级和方法级 Path 注解提取 Native 路由。"""
    routes: list[Route] = []

    for path in (root / "src/main/java").rglob("*.java"):
        text = read(path)
        class_match = re.search(
            r'@Path\("([^"]+)"\)\s*(?:@[\s\S]*?\s*)?public\s+class\s+\w+',
            text,
        )
        if not class_match:
            continue

        base_path = class_match.group(1)
        pending_method: str | None = None
        pending_path: str | None = None
        declaration_buffer = ""
        in_class = False

        for line in text.splitlines():
            if re.search(r"public\s+class\s+\w+", line):
                in_class = True
                pending_method = None
                pending_path = None
                declaration_buffer = ""
                continue
            if not in_class:
                continue

            methods = re.findall(r"@(" + HTTP_METHODS + r")\b", line)
            paths = re.findall(r'@Path\("([^"]*)"\)', line)
            if methods:
                pending_method = methods[-1]
            if paths:
                pending_path = paths[-1]

            if pending_method:
                declaration_buffer = f"{declaration_buffer} {line}".strip()
            else:
                declaration_buffer = ""

            declaration = re.search(
                r"\b(?:public|protected|private)\s+[^;{}]*\w+\s*\([^;{}]*\)",
                declaration_buffer,
            )
            if pending_method and declaration:
                route_path = "/api" + base_path + (pending_path or "")
                routes.append(
                    Route(pending_method, normalize_path(route_path), str(path.relative_to(root)))
                )
                pending_method = None
                pending_path = None
                declaration_buffer = ""

    return routes


def parse_phoenix(root: Path) -> list[Route]:
    """从 Phoenix Router 的 /api/v1 和 JWK scope 提取 HTTP 路由。"""
    text = read(root / "lib/keystone_phoenix_web/router.ex")
    scope = ""
    routes: list[Route] = []

    for line_number, line in enumerate(text.splitlines(), start=1):
        scope_match = re.search(r'\bscope\s+"([^"]*)"', line)
        if scope_match:
            scope = scope_match.group(1)
            continue

        route_match = re.match(r"\s*(get|post|put|patch|delete)\s+\"([^\"]+)\"", line)
        if route_match:
            method, path = route_match.groups()
            routes.append(
                Route(
                    method.upper(),
                    normalize_path(scope + path),
                    f"lib/keystone_phoenix_web/router.ex:{line_number}",
                )
            )

    return routes


def route_keys(routes: list[Route], prefix: str | None = None) -> set[tuple[str, str]]:
    """返回可比较的路由键，并可筛选外部业务前缀。"""
    return {
        (route.method, route.path)
        for route in routes
        if prefix is None or route.path.startswith(prefix)
    }


def duplicate_keys(routes: list[Route], prefix: str | None = None) -> set[tuple[str, str]]:
    """找出同一实现集合中的重复方法和路径。"""
    counts: dict[tuple[str, str], int] = {}
    for route in routes:
        key = (route.method, route.path)
        if prefix is None or route.path.startswith(prefix):
            counts[key] = counts.get(key, 0) + 1
    return {key for key, count in counts.items() if count > 1}


def check(name: str, routes: list[Route], errors: list[str], prefix: str) -> None:
    """检查实现中是否出现重复业务路由。"""
    duplicates = sorted(duplicate_keys(routes, prefix))
    if duplicates:
        errors.append(f"{name} 存在重复路由: {', '.join(f'{method} {path}' for method, path in duplicates)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="检查 Keystone 三端 API 路由和 admin-web 调用集合")
    parser.add_argument("--phoenix-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--native-root", type=Path, default=None)
    parser.add_argument("--admin-root", type=Path, default=None)
    args = parser.parse_args()

    phoenix_root = args.phoenix_root.resolve()
    native_root = (args.native_root or phoenix_root.parent / "keystone-native").resolve()
    admin_root = (args.admin_root or phoenix_root.parent / "keystone-admin-web").resolve()
    errors: list[str] = []

    admin_routes = parse_admin(admin_root)
    native_routes = parse_native(native_root)
    phoenix_routes = parse_phoenix(phoenix_root)
    business_prefix = "/api/v1/"
    admin_keys = route_keys(admin_routes, business_prefix)
    native_keys = route_keys(native_routes, business_prefix)
    phoenix_keys = route_keys(phoenix_routes, business_prefix)

    check("admin-web", admin_routes, errors, business_prefix)
    check("Native", native_routes, errors, business_prefix)
    check("Phoenix", phoenix_routes, errors, business_prefix)

    for consumer, expected in (("Native", native_keys), ("Phoenix", phoenix_keys)):
        missing = sorted(admin_keys - expected)
        if missing:
            errors.append(f"admin-web 调用但 {consumer} 缺少: {', '.join(f'{method} {path}' for method, path in missing)}")

    if native_keys != phoenix_keys:
        errors.append(
            "Native/Phoenix /api/v1 路由集合不一致: "
            f"Native-only={sorted(native_keys - phoenix_keys)}, Phoenix-only={sorted(phoenix_keys - native_keys)}"
        )

    admin_text = "\n".join(
        read(admin_root / relative)
        for relative in ("src/shared/api/client.ts", "src/shared/api/jobClient.ts", "src/shared/api/userFileClient.ts")
    )
    stale = [marker for marker in LEGACY_PATH_MARKERS if marker in admin_text]
    if stale:
        errors.append(f"admin-web 仍引用过时路径标识: {', '.join(stale)}")

    native_jwk = route_keys(native_routes, "/api/.well-known/")
    phoenix_jwk = route_keys(phoenix_routes, "/api/.well-known/")
    if native_jwk != phoenix_jwk:
        errors.append(f"Native/Phoenix JWK 路由不一致: Native={sorted(native_jwk)}, Phoenix={sorted(phoenix_jwk)}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"OK: admin-web uses {len(admin_keys)} API routes")
    print(f"OK: Native and Phoenix expose the same {len(native_keys)} /api/v1 routes")
    print(f"OK: JWK route set matches ({len(native_jwk)} route)")
    print("OK: no legacy admin-web API path markers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
