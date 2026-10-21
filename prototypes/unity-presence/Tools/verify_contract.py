#!/usr/bin/env python3
"""Offline source/fixture checks. These do not execute Flutter or Unity."""
import json
from pathlib import Path
import re
import unittest

PROJECT = Path(__file__).resolve().parents[1]
REPO = PROJECT.parents[1]
SCHEMA = json.loads((PROJECT / "Contract/avatar-presence-v1.schema.json").read_text())


def dart_enum(path, name):
    source = (REPO / path).read_text()
    match = re.search(r"enum " + name + r"\s*\{([^}]+)\}", source, re.S)
    return [v.strip() for v in match[1].split(",") if v.strip()]


class ContractSourceChecks(unittest.TestCase):
    def test_version_and_exact_fields_match_producer(self):
        source = (REPO / "lib/avatar/neura_avatar_runtime_bridge.dart").read_text()
        version = int(re.search(r"contractVersion = (\d+)", source)[1])
        fields = re.findall(r"'([a-z_]+)'\s*:", source.split("toJson()")[1].split("@override")[0])
        self.assertEqual(version, SCHEMA["properties"]["v"]["const"])
        self.assertEqual(set(fields), set(SCHEMA["properties"]))
        self.assertEqual(set(fields), set(SCHEMA["required"]))
        self.assertFalse(SCHEMA["additionalProperties"])

    def test_all_enum_domains_match_dart_and_consumer(self):
        mappings = {
            "phase": ("lib/services/neura_companion_presence.dart", "NeuraPresencePhase"),
            "stance": ("lib/neura_shell/models/neura_room_presence_profile.dart", "NeuraRoomStance"),
            "motion": ("lib/src/shell/shell_prefs.dart", "NeuraCompanionMotion"),
            "scale": ("lib/src/shell/shell_prefs.dart", "NeuraCompanionScale"),
        }
        consumer = (PROJECT / "Assets/Presence/Core/AvatarSnapshot.cs").read_text()
        for field, (path, enum) in mappings.items():
            expected = dart_enum(path, enum)
            self.assertEqual(expected, SCHEMA["properties"][field]["enum"])
            match = re.search(r'OneOf\(fields\["' + field + r'"\],([^)]*)\)', consumer, re.S)
            self.assertEqual(expected, re.findall(r'"([A-Za-z_]+)"', match[1]))

    def test_rooms_and_synthetic_room_stances_match_current_profiles(self):
        rooms = re.findall(r"id: '([^']+)'", (REPO / "lib/neura_shell/models/neura_room.dart").read_text())
        self.assertEqual(rooms, SCHEMA["properties"]["room_id"]["enum"])
        runtime = (PROJECT / "Assets/Presence/Runtime/PresencePrototype.cs").read_text()
        self.assertEqual(rooms, re.findall(r'"([a-z_]+)"', re.search(r"string\[\] Rooms = \{([^}]+)", runtime)[1]))
        consumer = (PROJECT / "Assets/Presence/Core/AvatarSnapshot.cs").read_text()
        self.assertEqual(rooms, re.findall(r'"([a-z_]+)"', re.search(r'OneOf\(fields\["room_id"\],([^)]*)\)', consumer, re.S)[1]))
        profiles = (REPO / "lib/neura_shell/models/neura_room_presence_profile.dart").read_text()
        stances = re.findall(r"stance: NeuraRoomStance\.([a-z]+)", profiles)
        self.assertEqual(stances, re.findall(r'"([a-z]+)"', re.search(r"string\[\] Stances = \{([^}]+)", runtime)[1]))

    def test_synthetic_fixtures_have_only_typed_presentation_fields(self):
        fixtures = json.loads((PROJECT / "Contract/synthetic-v1-states.json").read_text())
        self.assertEqual(6, len(fixtures))
        for snapshot in fixtures:
            self.assertEqual(set(SCHEMA["required"]), set(snapshot))
            for field, rule in SCHEMA["properties"].items():
                value = snapshot[field]
                if "enum" in rule:
                    self.assertIn(value, rule["enum"])
                elif rule["type"] == "integer":
                    self.assertIs(type(value), int)
                    self.assertEqual(value, rule["const"])
                else:
                    self.assertIs(type(value), bool)
            if snapshot["safe_mode"]:
                self.assertEqual("still", snapshot["motion"])

    def test_scene_and_build_settings_reference_existing_stable_guids(self):
        assets = PROJECT / "Assets"
        guids = set()
        for path in assets.rglob("*"):
            if path.suffix == ".meta":
                continue
            metadata = Path(str(path) + ".meta")
            self.assertTrue(metadata.is_file(), str(path.relative_to(PROJECT)))
            guid = re.search(r"^guid: ([0-9a-f]{32})$", metadata.read_text(), re.M)[1]
            self.assertNotIn(guid, guids)
            guids.add(guid)
        scene = assets / "Presence/Scenes/PresenceStage.unity"
        script_guid = re.search(r"guid: ([0-9a-f]{32})", (assets / "Presence/Runtime/PresencePrototype.cs.meta").read_text())[1]
        self.assertIn("guid: " + script_guid, scene.read_text())
        scene_guid = re.search(r"guid: ([0-9a-f]{32})", Path(str(scene) + ".meta").read_text())[1]
        settings = (PROJECT / "ProjectSettings/EditorBuildSettings.asset").read_text()
        self.assertIn("guid: " + scene_guid, settings)
        self.assertIn("path: Assets/Presence/Scenes/PresenceStage.unity", settings)

    def test_runtime_source_has_no_external_capability_apis(self):
        forbidden = r"System\.(?:Net|IO|Diagnostics)|DllImport|UnityWebRequest|Microphone\.|AudioSource|AudioListener|PlayerPrefs|Application\.OpenURL|\b(?:Thread|Process)\."
        for folder in ("Core", "Runtime"):
            for path in (PROJECT / "Assets/Presence" / folder).glob("*.cs"):
                self.assertIsNone(re.search(forbidden, path.read_text()), path.name)
        manifest = json.loads((PROJECT / "Packages/manifest.json").read_text())
        self.assertEqual({"com.unity.modules.imgui", "com.unity.modules.physics", "com.unity.test-framework"}, set(manifest["dependencies"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
