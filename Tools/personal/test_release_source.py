"""Check the SideStore contract against small packaged app fixtures."""

import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from release_source import APP_GROUP, BUNDLE_ID, SOURCE_URL, create_source, rename_app


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "Payload/NOOP.app"
        self.widget = self.app / "PlugIns/NOOPWidgets.appex"
        self.widget.mkdir(parents=True)
        self.info = {
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleDisplayName": "NOOP",
            "CFBundleShortVersionString": "1.2.1",
            "CFBundleVersion": "1.2.1",
            "AppGroupIdentifier": APP_GROUP,
            "MinimumOSVersion": "17.0",
            "NSBluetoothAlwaysUsageDescription": "Connect to your strap.",
        }
        self.write_info(self.app, self.info)
        self.write_info(self.widget, {**self.info, "CFBundleIdentifier": BUNDLE_ID + ".widgets"})

    def write_info(self, path, info):
        (path / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))

    def package(self):
        ipa = self.root / "NOOP-Lab-1.2.1.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            for file in self.app.rglob("*"):
                if file.is_file():
                    archive.write(file, file.relative_to(self.root).as_posix())
        return ipa

    def test_source_uses_packaged_metadata(self):
        ipa = self.package()
        source = create_source(ipa)
        app = source["apps"][0]
        self.assertEqual(source["sourceURL"], SOURCE_URL)
        self.assertEqual(app["bundleIdentifier"], BUNDLE_ID)
        self.assertEqual(app["size"], ipa.stat().st_size)
        self.assertEqual(app["versions"][0]["downloadURL"], "https://github.com/CommanderAstern/noop/releases/download/v1.2.1/NOOP-Lab-1.2.1.ipa")
        self.assertEqual(app["appPermissions"]["privacy"], {"NSBluetoothAlwaysUsageDescription": "Connect to your strap."})

    def test_rejects_upstream_identity_and_mismatched_widget(self):
        for key, wrong in (("CFBundleIdentifier", "com.noopapp.noop"), ("AppGroupIdentifier", "group.wrong"), ("CFBundleVersion", "99")):
            with self.subTest(key=key):
                info = {**self.info, "CFBundleIdentifier": BUNDLE_ID + ".widgets", key: wrong}
                self.write_info(self.widget, info)
                with self.assertRaises(ValueError):
                    create_source(self.package())

    def test_rejects_filename_version_mismatch(self):
        ipa = self.package()
        renamed = ipa.with_name("NOOP-Lab-1.2.2.ipa")
        ipa.rename(renamed)
        with self.assertRaises(ValueError):
            create_source(renamed)

    def test_personal_name_preserves_ids_and_localizations(self):
        locale = self.app / "en.lproj"
        locale.mkdir()
        strings = locale / "InfoPlist.strings"
        strings.write_bytes(plistlib.dumps({"CFBundleDisplayName": "NOOP", "NSBluetoothAlwaysUsageDescription": "Keep this translation."}))
        rename_app(self.app)
        app = plistlib.loads((self.app / "Info.plist").read_bytes())
        widget = plistlib.loads((self.widget / "Info.plist").read_bytes())
        self.assertEqual(app["CFBundleDisplayName"], "NOOP Lab")
        self.assertEqual(widget["CFBundleDisplayName"], "NOOP Lab")
        self.assertEqual(app["CFBundleIdentifier"], BUNDLE_ID)
        self.assertEqual(plistlib.loads(strings.read_bytes())["NSBluetoothAlwaysUsageDescription"], "Keep this translation.")


if __name__ == "__main__":
    unittest.main()
