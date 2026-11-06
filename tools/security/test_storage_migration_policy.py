"""Keep the legacy Android key readers until installed-upgrade acceptance.

This intentionally fails a future major upgrade even if ordinary widget tests
pass: mocked secure-storage channels cannot establish native key migration.
"""

from pathlib import Path
import re
import unittest


class StorageMigrationPolicyTest(unittest.TestCase):
    def test_locked_storage_keeps_the_v10_migration_stage(self):
        root = Path(__file__).resolve().parents[2]
        manifest = (root / "pubspec.yaml").read_text()
        lock = (root / "pubspec.lock").read_text()
        declared = re.search(r"^  flutter_secure_storage: (\S+)\s*$", manifest, re.M)
        self.assertIsNotNone(declared)
        self.assertRegex(
            declared[1], r"^10\.\d+\.\d+$",
            "Keep an exact v10 migration pin; v11 needs installed-upgrade evidence, including skipped versions.",
        )
        locked = re.search(
            r'^  flutter_secure_storage:\n(?:(?!^  \S).|\n)*?^    version: "([^"]+)"',
            lock, re.M,
        )
        self.assertIsNotNone(locked)
        self.assertEqual(locked[1], declared[1])


if __name__ == "__main__":
    unittest.main()
