import unittest

from check_android_update import upgrade_blockers


class SameSignerUpgradeTests(unittest.TestCase):
    def setUp(self):
        self.old = dict(package="com.neurocompanion.app", version_code=434, signers_sha256=["a"])
        self.new = dict(self.old, version_code=667)

    def test_newer_matching_package_and_signer(self):
        self.assertEqual(upgrade_blockers(self.old, self.new), [])

    def test_different_signer_with_higher_version(self):
        self.assertTrue(upgrade_blockers(self.old, dict(self.new, signers_sha256=["b"])))

    def test_different_package_or_nonincreasing_version(self):
        for candidate in (dict(self.new, package="other.app"), self.old, dict(self.new, version_code=1)):
            with self.subTest(candidate=candidate):
                self.assertTrue(upgrade_blockers(self.old, candidate))
