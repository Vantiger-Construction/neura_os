#!/usr/bin/env python3
"""Offline source/fixture checks. These do not execute Flutter or Unity."""
import json
from pathlib import Path
import re
import unittest

PROJECT = Path(__file__).resolve().parents[1]
REPO = PROJECT.parents[1]
SCHEMA = json.loads((PROJECT / "Contract/avatar-presence-v2.schema.json").read_text())
# v1 is still accepted by every receiver; its schema must not drift.
SCHEMA_V1 = json.loads((PROJECT / "Contract/avatar-presence-v1.schema.json").read_text())
STAGE_FIELDS = ("lighting", "camera", "activity")


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
        # v2 is exactly v1 plus the three stage fields.
        self.assertEqual(SCHEMA_V1["properties"]["v"]["const"], 1)
        self.assertEqual(set(SCHEMA["required"]) - set(SCHEMA_V1["required"]), set(STAGE_FIELDS))
        self.assertFalse(SCHEMA_V1["additionalProperties"])

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
            self.assertEqual(expected, SCHEMA_V1["properties"][field]["enum"])
        stage = {
            "lighting": "NeuraStageLighting",
            "camera": "NeuraStageCamera",
            "activity": "NeuraCompanionActivity",
        }
        for field, enum in stage.items():
            expected = dart_enum("lib/avatar/neura_avatar_runtime_bridge.dart", enum)
            self.assertEqual(expected, SCHEMA["properties"][field]["enum"])
            match = re.search(r"OneOf\(" + field + r",([^)]*)\)", consumer, re.S)
            self.assertEqual(expected, re.findall(r'"([A-Za-z_]+)"', match[1]))
        rust = (REPO / "rust/src/presence_relay.rs").read_text()
        for field, enum in (("lighting", "Lighting"), ("camera", "Camera"), ("activity", "Activity")):
            variants = re.search(r"enum " + enum + r" \{([^}]+)\}", rust)[1]
            names = [re.sub(r"(?<!^)([A-Z])", r"_\1", v.strip()).lower() for v in variants.split(",") if v.strip()]
            self.assertEqual(SCHEMA["properties"][field]["enum"], names)

    def test_rooms_and_synthetic_room_stances_match_current_profiles(self):
        rooms = re.findall(r"id: '([^']+)'", (REPO / "lib/neura_shell/models/neura_room.dart").read_text())
        self.assertEqual(rooms, SCHEMA["properties"]["room_id"]["enum"])
        # v1 lists every room except the one v2 added.
        self.assertEqual([r for r in rooms if r != "her_suite"], SCHEMA_V1["properties"]["room_id"]["enum"])
        rust = (REPO / "rust/src/presence_relay.rs").read_text()
        variants = re.search(r"enum Room \{([^}]+)\}", rust)[1]
        names = [re.sub(r"(?<!^)([A-Z])", r"_\1", line.strip().rstrip(",")).lower()
                 for line in variants.splitlines() if line.strip() and not line.strip().startswith("//")]
        self.assertEqual(rooms, names)
        runtime = (PROJECT / "Assets/Presence/Runtime/PresencePrototype.cs").read_text()
        self.assertEqual(rooms, re.findall(r'"([a-z_]+)"', re.search(r"string\[\] Rooms = \{([^}]+)", runtime)[1]))
        consumer = (PROJECT / "Assets/Presence/Core/AvatarSnapshot.cs").read_text()
        self.assertEqual(rooms, re.findall(r'"([a-z_]+)"', re.search(r'OneOf\(fields\["room_id"\],([^)]*)\)', consumer, re.S)[1]))
        profiles = (REPO / "lib/neura_shell/models/neura_room_presence_profile.dart").read_text()
        stances = re.findall(r"stance: NeuraRoomStance\.([a-z]+)", profiles)
        self.assertEqual(stances, re.findall(r'"([a-z]+)"', re.search(r"string\[\] Stances = \{([^}]+)", runtime)[1]))

    def test_synthetic_fixtures_have_only_typed_presentation_fields(self):
        for name, schema, count in (
            ("synthetic-v1-states.json", SCHEMA_V1, 6),
            ("synthetic-v2-states.json", SCHEMA, 7),
        ):
            self._check_fixtures(json.loads((PROJECT / "Contract" / name).read_text()), schema, count)

    def _check_fixtures(self, fixtures, schema, count):
        self.assertEqual(count, len(fixtures))
        for snapshot in fixtures:
            self.assertEqual(set(schema["required"]), set(snapshot))
            for field, rule in schema["properties"].items():
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
                if "activity" in snapshot:
                    self.assertEqual("present", snapshot["activity"])

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

    def test_live_bridge_is_isolated_opt_in_and_credential_safe(self):
        bridge = PROJECT / "Assets/Presence/Bridge"
        sources = {path: path.read_text() for path in bridge.rglob("*.cs")}
        self.assertEqual(
            {"PresenceBridgeConfig.cs", "PresenceEnvelope.cs", "PresenceRelayClient.cs", "PresenceLiveBridge.cs"},
            {path.name for path in sources},
        )
        forbidden = r"System\.(?:IO|Diagnostics)|DllImport|UnityWebRequest|Microphone\.|AudioSource|AudioListener|PlayerPrefs|Application\.OpenURL|\bProcess\.|Debug\.Log|Console\.|\bFile\.|GetCommandLineArgs|SerializeField"
        for path, text in sources.items():
            self.assertIsNone(re.search(forbidden, text), path.name)
            if path.parent.name == "Protocol":
                # Only the relay client networks, and only over WebSockets.
                self.assertIsNone(re.search(r"System\.Net(?!\.WebSockets)|\bDns\.|\b(?:Socket|TcpClient|UdpClient|HttpClient)\b", text), path.name)
            else:
                self.assertIsNone(re.search(r"System\.Net", text), path.name)
        config = sources[bridge / "Protocol/PresenceBridgeConfig.cs"]
        self.assertIn("internal string Token", config)
        self.assertNotIn("localhost", config)
        # The credential is read only from the launcher-set environment.
        reads = [p.name for p, t in sources.items() if "GetEnvironmentVariable" in t]
        self.assertEqual(["PresenceLiveBridge.cs"], reads)
        for folder, name in (("Protocol", "Neura.Presence.Bridge.Protocol"), ("Live", "Neura.Presence.Bridge")):
            asmdef = json.loads((bridge / folder / (name + ".asmdef")).read_text())
            self.assertEqual(["WebGL"], asmdef["excludePlatforms"])
        for folder, name in (("Core", "Neura.Presence.Core"), ("Runtime", "Neura.Presence.Runtime")):
            asmdef = json.loads((PROJECT / "Assets/Presence" / folder / (name + ".asmdef")).read_text())
            self.assertFalse(any("Bridge" in ref for ref in asmdef.get("references", [])), name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
