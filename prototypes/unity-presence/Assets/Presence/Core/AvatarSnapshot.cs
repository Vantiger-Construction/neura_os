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
        public const int Version = 1;
        public const int MaxJsonCharacters = 512;
        public string RoomId { get; private set; }
        public string Phase { get; private set; }
        public string Stance { get; private set; }
        public string Motion { get; private set; }
        public string Scale { get; private set; }
        public bool SafeMode { get; private set; }

        private AvatarSnapshot(string room, string phase, string stance,
            string motion, string scale, bool safe)
        {
            RoomId = room;
            SafeMode = safe || phase == "safeMode";
            Phase = SafeMode ? "safeMode" : phase;
            Stance = stance;
            Motion = SafeMode ? "still" : motion;
            Scale = scale;
        }

        public static AvatarSnapshot SafeDefault()
        {
            return new AvatarSnapshot("penthouse", "safeMode", "welcoming",
                "still", "standard", true);
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
            if (fields.Count != 7) { error = SnapshotError.MissingField; return false; }
            if (fields["v"] != "1") { error = SnapshotError.UnsupportedVersion; return false; }
            if (!OneOf(fields["room_id"], "penthouse", "reflection_bay", "joy_lounge",
                    "mood_den", "dream_atrium", "legacy_vault") ||
                !OneOf(fields["phase"], "idle", "thinking", "speaking", "listening", "safeMode") ||
                !OneOf(fields["stance"], "welcoming", "reflective", "playful", "grounding", "dreaming", "guardian") ||
                !OneOf(fields["motion"], "still", "subtle", "expressive") ||
                !OneOf(fields["scale"], "compact", "standard", "large"))
            {
                error = SnapshotError.InvalidValue;
                return false;
            }
            snapshot = new AvatarSnapshot(fields["room_id"], fields["phase"],
                fields["stance"], fields["motion"], fields["scale"], fields["safe_mode"] == "true");
            error = SnapshotError.None;
            return true;
        }

        private static bool AllowedKey(string key)
        {
            return OneOf(key, "v", "room_id", "phase", "stance", "motion", "scale", "safe_mode");
        }

        private static bool OneOf(string value, params string[] allowed)
        {
            return Array.IndexOf(allowed, value) >= 0;
        }

        // A bounded flat JSON profile: seven typed fields, ASCII enum tokens only.
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
