# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class HookInstallTests(unittest.TestCase):
    def test_constructor_installs_hooks_unconditionally(self):
        """A failed preferences read at load must not leave the process unhooked."""
        source = (ROOT / "Hooks.xm").read_text()
        constructor = source[source.index("%ctor"):]
        body = constructor[constructor.index("{"):]
        install = body.index("%init(AVNPlaybackHooks);")
        self.assertNotIn("if (AVNRuntimeEnabled())", body[:install],
                         "hooks must install even when preferences are unreadable at load")


class ApplicationDefaultTests(unittest.TestCase):
    def test_missing_app_key_falls_back_to_global_enabled(self):
        """The global switch alone must enable acceleration for every app."""
        source = (ROOT / "ASPPaths.h").read_text()
        match = re.search(r'values\[@"AppEnabled"\]\s*=\s*(.+?);', source)
        self.assertIsNotNone(match, "AppEnabled assignment not found")
        expression = match.group(1)
        self.assertIn('stored[@"Enabled"]', expression)
        self.assertNotIn("@NO", expression,
                         "an app without an explicit key must not start disabled")


if __name__ == "__main__":
    unittest.main()
