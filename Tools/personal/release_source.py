"""Build the personal SideStore source from the packaged app's actual metadata."""

import argparse
import json
import plistlib
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

REPOSITORY = "CommanderAstern/noop"
BUNDLE_ID = "com.commanderastern.noop"
APP_GROUP = "group.com.commanderastern.noop.staging"
SOURCE_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/altstore-source.json"


def rename_app(app):
    """Name the app and widget without changing the build's shared identifiers."""
    for info in (app / "Info.plist", app / "PlugIns/NOOPWidgets.appex/Info.plist"):
        metadata = plistlib.loads(info.read_bytes())
        metadata["CFBundleDisplayName"] = "NOOP Lab"
        info.write_bytes(plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY))
    # Localized display names otherwise override the main Info.plist value.
    for strings in app.glob("*.lproj/InfoPlist.strings"):
        values = plistlib.loads(strings.read_bytes())
        if "CFBundleDisplayName" in values:
            values["CFBundleDisplayName"] = "NOOP Lab"
            strings.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))


def create_source(ipa):
    """Reject mismatched app/widget identities and derive accurate install metadata."""
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        apps = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(apps) != 1:
            raise ValueError("IPA must contain exactly one app")
        root = apps[0].removesuffix("Info.plist")
        app = plistlib.loads(archive.read(apps[0]))
        widget = plistlib.loads(archive.read(root + "PlugIns/NOOPWidgets.appex/Info.plist"))
        if app["CFBundleIdentifier"] != BUNDLE_ID:
            raise ValueError("Wrong app bundle identity")
        if widget["CFBundleIdentifier"] != BUNDLE_ID + ".widgets":
            raise ValueError("Wrong widget bundle identity")
        for info in (app, widget):
            if info.get("AppGroupIdentifier") != APP_GROUP:
                raise ValueError("Wrong shared App Group")
            for key in ("CFBundleShortVersionString", "CFBundleVersion"):
                if info[key] != app[key]:
                    raise ValueError("App and widget versions differ")
        version = app["CFBundleShortVersionString"]
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise ValueError("Version must have three numeric components")
        if ipa.name != f"NOOP-Lab-{version}.ipa":
            raise ValueError("IPA filename and bundle version differ")

    date = datetime.now(timezone.utc).isoformat(timespec="seconds")
    icon = f"https://raw.githubusercontent.com/{REPOSITORY}/personal/Strand/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
    description = "Personal NOOP build based on ryanbr/noop. Reads your strap over Bluetooth and stores data on your device. Independent of WHOOP. This app has separate data from your original NOOP installation."
    release = {
        "version": version,
        "buildVersion": app["CFBundleVersion"],
        "date": date,
        "localizedDescription": f"NOOP Lab {version}. See the GitHub release for build details.",
        "downloadURL": f"https://github.com/{REPOSITORY}/releases/download/v{version}/{ipa.name}",
        "size": ipa.stat().st_size,
        "minOSVersion": app["MinimumOSVersion"],
    }
    entry = {
        "name": "NOOP Lab",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": "CommanderAstern · NOOP contributors",
        "subtitle": "Your personal WHOOP companion",
        "localizedDescription": description,
        "iconURL": icon,
        "tintColor": "44E2B0",
        "category": "healthcare-fitness",
        "screenshotURLs": [],
        "versions": [release],
        "appPermissions": {
            "entitlements": ["com.apple.developer.healthkit", "com.apple.developer.healthkit.access", "com.apple.security.application-groups"],
            "privacy": {key: value for key, value in app.items() if key.startswith("NS") and key.endswith("UsageDescription")},
        },
        "version": version,
        "buildVersion": app["CFBundleVersion"],
        "versionDate": date,
        "versionDescription": release["localizedDescription"],
        "downloadURL": release["downloadURL"],
        "size": release["size"],
        "minOSVersion": release["minOSVersion"],
    }
    return {"name": "CommanderAstern NOOP Lab", "identifier": BUNDLE_ID + ".source", "sourceURL": SOURCE_URL, "subtitle": "Personal builds and updates", "description": description, "iconURL": icon, "website": f"https://github.com/{REPOSITORY}", "tintColor": "44E2B0", "apps": [entry], "news": []}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("rename", "source"))
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    args = parser.parse_args()
    if args.command == "rename":
        rename_app(args.input)
    else:
        if args.output is None:
            parser.error("source requires an output path")
        args.output.write_text(json.dumps(create_source(args.input), indent=2) + "\n", encoding="utf-8")
