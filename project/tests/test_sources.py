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

    def test_settings_lists_a_missing_key_as_enabled(self):
        """The Settings UI must group an unset app the same way the runtime reads it."""
        source = (ROOT / "settings/AVNSettings.m").read_text()
        self.assertIn("BOOL appEnabled = stored ? [stored boolValue] : YES;", source)


class NativeTimerTests(unittest.TestCase):
    def test_hooks_install_native_timer_swizzles(self):
        """Native SDK countdowns are only accelerated through the NSTimer hooks."""
        source = (ROOT / "Hooks.xm").read_text()
        self.assertIn("%group AVNTimerHooks", source)
        self.assertIn("%init(AVNTimerHooks);", source)
        self.assertIn("scheduledTimerWithTimeInterval:", source)

    def test_native_timers_require_automatic_mode(self):
        """Manual mode must leave native countdowns at real speed."""
        source = (ROOT / "Runtime.mm").read_text()
        match = re.search(r"ASPTimerConfigure\(([^;]+)\);", source)
        self.assertIsNotNone(match, "ASPTimerConfigure call not found")
        expression = match.group(1)
        for required in ("options.enabled", "options.timers", "options.automatic"):
            self.assertIn(required, expression)

    def test_compression_skips_short_and_long_intervals(self):
        """Animation and network timers must keep their real speed."""
        source = (ROOT / "ASPTimers.mm").read_text()
        self.assertIn("interval < kASPTimerMinimum || interval > kASPTimerMaximum", source)
        self.assertIn("kASPTimerMinimum = 0.5", source)
        self.assertIn("kASPTimerMaximum = 30.0", source)


if __name__ == "__main__":
    unittest.main()
