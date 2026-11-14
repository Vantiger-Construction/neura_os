using System;
using System.Collections.Generic;

namespace Neura.Presence
{
    public enum SnapshotError
    {
        None, InvalidStructure, PayloadTooLarge, UnknownField, DuplicateField,
        MissingField, UnsupportedVersion, InvalidValue
    }

    // Deliberately independent of Unity, transport, storage and app services.
    public sealed class AvatarSnapshot
    {
        // v2 added her_suite, lighting, camera and activity. v1 input is still
        // accepted and reads as standard lighting, follow camera, present.
        public const int Version = 2;
        public const int MinVersion = 1;
        public const int MaxJsonCharacters = 512;
        public int SourceVersion { get; private set; }
        public string RoomId { get; private set; }
        public string Phase { get; private set; }
        public string Stance { get; private set; }
        public string Motion { get; private set; }
        public string Scale { get; private set; }
        public bool SafeMode { get; private set; }
        public string Lighting { get; private set; }
        public string Camera { get; private set; }
        public string Activity { get; private set; }
        public bool Resting { get { return Activity == "resting"; } }

        private AvatarSnapshot(int version, string room, string phase, string stance,
            string motion, string scale, bool safe, string lighting, string camera,
            string activity)
        {
            SourceVersion = version;
            RoomId = room;
            SafeMode = safe || phase == "safeMode";
            Phase = SafeMode ? "safeMode" : phase;
            Stance = stance;
            Motion = SafeMode ? "still" : motion;
            Scale = scale;
            Lighting = lighting;
            Camera = camera;
            Activity = SafeMode ? "present" : activity;
        }

        public static AvatarSnapshot SafeDefault()
        {
            return new AvatarSnapshot(Version, "penthouse", "safeMode", "welcoming",
                "still", "standard", true, "standard", "follow", "present");
        }

        public static bool TryParse(string json, out AvatarSnapshot snapshot,
            out SnapshotError error)
        {
            snapshot = null;
            error = SnapshotError.InvalidStructure;
            if (json == null) return false;
            if (json.Length > MaxJsonCharacters)
            {
                error = SnapshotError.PayloadTooLarge;
                return false;
            }
            var reader = new FlatReader(json);
            var fields = new Dictionary<string, string>(StringComparer.Ordinal);
            if (!reader.Take('{')) return false;
            do
            {
                string key, value;
                if (!reader.ReadToken(out key)) return false;
                if (!AllowedKey(key)) { error = SnapshotError.UnknownField; return false; }
                if (fields.ContainsKey(key)) { error = SnapshotError.DuplicateField; return false; }
                if (!reader.Take(':')) return false;
                if (key == "v")
                {
                    if (!reader.ReadInteger(out value)) return false;
                }
                else if (key == "safe_mode")
                {
                    if (!reader.ReadBoolean(out value)) return false;
                }
                else if (!reader.ReadToken(out value)) return false;
                fields.Add(key, value);
            } while (reader.Take(','));
            if (!reader.Take('}') || !reader.AtEnd) return false;
            string versionText;
            if (!fields.TryGetValue("v", out versionText)) { error = SnapshotError.MissingField; return false; }
            if (versionText != "1" && versionText != "2") { error = SnapshotError.UnsupportedVersion; return false; }
            int version = versionText == "2" ? 2 : 1;
            bool hasStage = fields.ContainsKey("lighting") || fields.ContainsKey("camera") || fields.ContainsKey("activity");
            // v1 can't carry v2's stage fields.
            if (version == 1 && hasStage) { error = SnapshotError.UnknownField; return false; }
            if (fields.Count != (version == 2 ? 10 : 7)) { error = SnapshotError.MissingField; return false; }
            foreach (string required in new[] { "room_id", "phase", "stance", "motion", "scale", "safe_mode" })
                if (!fields.ContainsKey(required)) { error = SnapshotError.MissingField; return false; }
            if (version == 2 && (!fields.ContainsKey("lighting") || !fields.ContainsKey("camera") || !fields.ContainsKey("activity")))
            { error = SnapshotError.MissingField; return false; }
            // ...nor name v2's room.
            if (version == 1 && fields["room_id"] == "her_suite") { error = SnapshotError.InvalidValue; return false; }
            string lighting = version == 2 ? fields["lighting"] : "standard";
            string camera = version == 2 ? fields["camera"] : "follow";
            string activity = version == 2 ? fields["activity"] : "present";
            if (!OneOf(lighting, "standard", "gold", "aurora", "dusk") ||
                !OneOf(camera, "follow", "wide", "face") ||
                !OneOf(activity, "present", "resting"))
            {
                error = SnapshotError.InvalidValue;
                return false;
            }
            if (!OneOf(fields["room_id"], "penthouse", "reflection_bay", "joy_lounge",
                    "mood_den", "dream_atrium", "legacy_vault", "her_suite") ||
                !OneOf(fields["phase"], "idle", "thinking", "speaking", "listening", "safeMode") ||
                !OneOf(fields["stance"], "welcoming", "reflective", "playful", "grounding", "dreaming", "guardian") ||
                !OneOf(fields["motion"], "still", "subtle", "expressive") ||
                !OneOf(fields["scale"], "compact", "standard", "large"))
            {
                error = SnapshotError.InvalidValue;
                return false;
            }
            // Resting belongs to Her Suite; no other room has her window.
            if (activity == "resting" && fields["room_id"] != "her_suite")
            {
                error = SnapshotError.InvalidValue;
                return false;
            }
            snapshot = new AvatarSnapshot(version, fields["room_id"], fields["phase"],
                fields["stance"], fields["motion"], fields["scale"], fields["safe_mode"] == "true",
                lighting, camera, activity);
            error = SnapshotError.None;
            return true;
        }

        private static bool AllowedKey(string key)
        {
            return OneOf(key, "v", "room_id", "phase", "stance", "motion", "scale", "safe_mode",
                "lighting", "camera", "activity");
        }

        private static bool OneOf(string value, params string[] allowed)
        {
            return Array.IndexOf(allowed, value) >= 0;
        }

        // A bounded flat JSON profile: seven (v1) or ten (v2) typed fields, ASCII enum tokens only.
        // No ignored fields, escaped strings, nested objects, arrays or raw text.
        // Dart toJson/jsonEncode emits this profile. Field order is unrestricted.
        private sealed class FlatReader
        {
            private readonly string text;
            private int offset;
            public FlatReader(string text) { this.text = text; }
            private void Space()
            {
                while (offset < text.Length && (text[offset] == ' ' || text[offset] == '\t' ||
                    text[offset] == '\r' || text[offset] == '\n')) offset++;
            }
            public bool AtEnd { get { Space(); return offset == text.Length; } }
            public bool Take(char character)
            {
                Space();
                if (offset >= text.Length || text[offset] != character) return false;
                offset++;
                return true;
            }
            public bool ReadToken(out string token)
            {
                token = null;
                if (!Take('"')) return false;
                int start = offset;
                while (offset < text.Length && text[offset] != '"')
                {
                    char c = text[offset++];
                    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_')) return false;
                }
                if (offset == text.Length || offset == start) return false;
                token = text.Substring(start, offset - start);
                offset++;
                return true;
            }
            public bool ReadInteger(out string value)
            {
                Space();
                int start = offset;
                while (offset < text.Length && text[offset] >= '0' && text[offset] <= '9') offset++;
                value = text.Substring(start, offset - start);
                return value.Length > 0 && (value.Length == 1 || value[0] != '0');
            }
            public bool ReadBoolean(out string value)
            {
                Space();
                foreach (string candidate in new[] { "true", "false" })
                {
                    if (offset + candidate.Length <= text.Length &&
                        string.CompareOrdinal(text, offset, candidate, 0, candidate.Length) == 0)
                    {
                        offset += candidate.Length;
                        value = candidate;
                        return true;
                    }
                }
                value = null;
                return false;
            }
        }
    }
}
