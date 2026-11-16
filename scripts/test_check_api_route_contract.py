#!/usr/bin/env python3
"""检查 admin-web 路由解析器能够处理三元表达式路径。"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_api_route_contract.py")
SPEC = importlib.util.spec_from_file_location("route_contract", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class AdminRouteParserTest(unittest.TestCase):
    def test_ternary_paths_are_counted_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src/shared/api").mkdir(parents=True)
            source = """
            async function listPosts(filters?: object) {
              return request(filters ? `/posts?page=1` : '/posts')
            }
            async function listRoles(filters?: object) {
              return request(filters ? `/roles?page=1` : '/roles')
            }
            async function getUser(id: string) {
              return request(`/users/${id}`)
            }
            async function updateUser() {
              return request('/users', { method: 'POST', body: '/not-a-route' })
            }
            """
            for name in ("client.ts", "jobClient.ts", "userFileClient.ts"):
                (root / "src/shared/api" / name).write_text(source, encoding="utf-8")

            routes = MODULE.parse_admin(root)
            keys = MODULE.route_keys(routes, "/api/v1/")

        self.assertEqual(
            keys,
            {
                ("GET", "/api/v1/posts"),
                ("GET", "/api/v1/roles"),
                ("GET", "/api/v1/users/:param"),
                ("POST", "/api/v1/users"),
            },
        )


if __name__ == "__main__":
    unittest.main()
