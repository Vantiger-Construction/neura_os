namespace Neura.Presence.Bridge
{
    public enum PresenceFrameKind { Ignored, Presence, Cleared, Invalid }

    // Reads one neura_api relay frame. The server's envelope layout is fixed
    // (`{"v":1,"kind":"...","id":"<uuid>","data":{...}}`, pinned by the
    // neura_api presence tests), so this matches it exactly rather than
    // deserializing general JSON. The snapshot itself is then validated by
    // the strict AvatarSnapshot parser.
    public static class PresenceEnvelope
    {
        public const int MaxFrameCharacters = 1024;
        public const string SubscribeMessage = "{\"v\":1,\"kind\":\"presence_subscribe\",\"data\":{}}";

        private const string Prefix = "{\"v\":1,\"kind\":\"";
        private const string IdField = "\",\"id\":\"";
        private const string DataField = "\",\"data\":";
        private const int IdLength = 36;

        public static PresenceFrameKind Read(string text, out string snapshotJson)
        {
            snapshotJson = null;
            if (text == null || text.Length > MaxFrameCharacters) return PresenceFrameKind.Invalid;
            if (!text.StartsWith(Prefix, System.StringComparison.Ordinal)) return PresenceFrameKind.Invalid;

            int offset = Prefix.Length;
            int kindStart = offset;
            while (offset < text.Length && offset - kindStart <= 40 && IsKindChar(text[offset])) offset++;
            int kindLength = offset - kindStart;
            if (kindLength == 0 || kindLength > 40) return PresenceFrameKind.Invalid;
            string kind = text.Substring(kindStart, kindLength);

            if (string.CompareOrdinal(text, offset, IdField, 0, IdField.Length) != 0) return PresenceFrameKind.Invalid;
            offset += IdField.Length;
            if (offset + IdLength > text.Length) return PresenceFrameKind.Invalid;
            for (int i = 0; i < IdLength; i++)
                if (!IsIdChar(text[offset + i])) return PresenceFrameKind.Invalid;
            offset += IdLength;

            if (string.CompareOrdinal(text, offset, DataField, 0, DataField.Length) != 0) return PresenceFrameKind.Invalid;
            offset += DataField.Length;
            // Both the envelope and its flat data object must close: `...}}`.
            if (offset >= text.Length - 2 || text[offset] != '{' ||
                text[text.Length - 1] != '}' || text[text.Length - 2] != '}')
                return PresenceFrameKind.Invalid;
            string data = text.Substring(offset, text.Length - 1 - offset);

            switch (kind)
            {
                case "avatar_presence":
                    snapshotJson = data;
                    return PresenceFrameKind.Presence;
                case "avatar_presence_cleared":
                    return PresenceFrameKind.Cleared;
                default:
                    // hello, error and other replies carry no presentation.
                    return PresenceFrameKind.Ignored;
            }
        }

        private static bool IsKindChar(char c) { return (c >= 'a' && c <= 'z') || c == '_'; }
        private static bool IsIdChar(char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || c == '-'; }
    }
}
