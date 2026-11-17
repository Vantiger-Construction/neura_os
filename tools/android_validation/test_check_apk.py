import copy
import unittest

from check_apk import compare


class ApkRegressionTests(unittest.TestCase):
    def setUp(self):
        self.previous = dict(status='signature-verified', package='com.neurocompanion.app',
                             permissions=['android.permission.RECORD_AUDIO'], min_sdk=24,
                             target_sdk=36, native_abis=['arm64-v8a'])

    def test_unchanged_static_identity_is_not_device_acceptance(self):
        report = compare(self.previous, copy.deepcopy(self.previous))
        self.assertIn('UNVERIFIED', report['acceptance'])

    def test_added_permissions_or_changed_sdk_abi_or_application_id_fail(self):
        for key, value in [('permissions', ['android.permission.RECORD_AUDIO', 'android.permission.CAMERA']),
                           ('min_sdk', 26), ('target_sdk', 37), ('native_abis', ['x86_64']),
                           ('package', 'other.app')]:
            candidate = dict(self.previous, **{key: value})
            with self.subTest(key=key), self.assertRaises(ValueError):
                compare(self.previous, candidate)

    def test_incomplete_receipt_cannot_pass(self):
        with self.assertRaises(ValueError):
            compare(self.previous, dict(self.previous, status='incomplete'))


if __name__ == '__main__':
    unittest.main()
