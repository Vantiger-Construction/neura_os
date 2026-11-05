using System;
using System.Collections.Generic;
using Neura.Presence.Bridge;

namespace Neura.Presence.Tests
{
    // Live-bridge protocol scenarios, shared by the console harness and Unity
    // EditMode. Frames use the exact layout neura_api's presence tests pin.
    public static class BridgeCases
    {
        private const string Token = "abababababababababababababababababababababababababababababababab";
        private const string Id = "0f8fad5b-d9cb-469f-a165-70867728950e";
        private const string Snapshot = "{\"motion\":\"subtle\",\"phase\":\"thinking\",\"room_id\":\"mood_den\",\"safe_mode\":false,\"scale\":\"standard\",\"stance\":\"grounding\",\"v\":1}";

        private static readonly Dictionary<string, Action> Cases = new Dictionary<string, Action>
        {
            { "bridge_disabled_without_launcher_settings", () => Expect(null, null, PresenceBridgeConfigError.Disabled) },
            { "bridge_accepts_numeric_loopback_only", LoopbackOnly },
            { "bridge_requires_a_session_token", TokenRules },
            { "bridge_config_text_never_contains_token", () => Check(!Config("127.0.0.1:8790", Token).ToString().Contains(Token), "Token leaked into ToString.") },
            { "envelope_reads_presence_frame", ReadsPresence },
            { "envelope_reads_cleared_and_ignores_replies", ClearedAndIgnored },
            { "envelope_rejects_malformed_frames", RejectsMalformed },
            { "relay_frame_drives_session_and_cleared_resets", FrameDrivesSession },
            { "relay_frame_with_private_field_is_rejected", PrivateFieldRejected }
        };

        public static IEnumerable<string> Names { get { return Cases.Keys; } }
        public static void Run(string name) { Cases[name](); }

        private static void Check(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }

        private static string Frame(string kind, string data)
        {
            return "{\"v\":1,\"kind\":\"" + kind + "\",\"id\":\"" + Id + "\",\"data\":" + data + "}";
        }

        private static PresenceBridgeConfig Config(string address, string token)
        {
            PresenceBridgeConfig config;
            PresenceBridgeConfigError error;
            Check(PresenceBridgeConfig.TryCreate(Env(address, token), out config, out error), "Expected valid config: " + error);
            return config;
        }

        private static Func<string, string> Env(string address, string token)
        {
            return name => name == PresenceBridgeConfig.AddressVariable ? address
                : name == PresenceBridgeConfig.TokenVariable ? token : null;
        }

        private static void Expect(string address, string token, PresenceBridgeConfigError expected)
        {
            PresenceBridgeConfig config;
            PresenceBridgeConfigError error;
            Check(!PresenceBridgeConfig.TryCreate(Env(address, token), out config, out error), "Config unexpectedly valid.");
            Check(config == null && error == expected, "Expected " + expected + " but got " + error);
        }

        private static void LoopbackOnly()
        {
            Check(Config("127.0.0.1:8790", Token).Endpoint.ToString() == "ws://127.0.0.1:8790/", "IPv4 endpoint.");
            Check(Config("127.4.5.6:1", Token).Endpoint.IsLoopback, "127/8 endpoint.");
            Check(Config("[::1]:65535", Token).Endpoint.IsLoopback, "IPv6 endpoint.");
            foreach (string bad in new[] {
                "localhost:8790", "0.0.0.0:8790", "192.168.1.5:8790", "10.0.0.1:8790", "127.0.0.1",
                "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:08790", "127.0.0.1:+80", "127.0.0.01:8790",
                "127.0.0.256:8790", "127.0.0:8790", "[::]:8790", "evil.example:80", "127.0.0.1:80/x", ""
            })
                Expect(bad, Token, PresenceBridgeConfigError.InvalidAddress);
        }

        private static void TokenRules()
        {
            Expect("127.0.0.1:8790", null, PresenceBridgeConfigError.InvalidToken);
            Expect("127.0.0.1:8790", Token.Substring(1), PresenceBridgeConfigError.InvalidToken);
            Expect("127.0.0.1:8790", Token + "a", PresenceBridgeConfigError.InvalidToken);
            Expect("127.0.0.1:8790", Token.Substring(1) + "g", PresenceBridgeConfigError.InvalidToken);
            Expect(null, Token, PresenceBridgeConfigError.InvalidAddress);
            Check(PresenceBridgeConfig.IsSessionToken(Token.ToUpperInvariant()), "Uppercase hex accepted by neura_api.");
        }

        private static void ReadsPresence()
        {
            string json;
            Check(PresenceEnvelope.Read(Frame("avatar_presence", Snapshot), out json) == PresenceFrameKind.Presence, "Presence kind.");
            Check(json == Snapshot, "Snapshot extracted verbatim.");
        }

        private static void ClearedAndIgnored()
        {
            string json;
            Check(PresenceEnvelope.Read(Frame("avatar_presence_cleared", "{\"reason\":\"stale\"}"), out json) == PresenceFrameKind.Cleared && json == null, "Cleared.");
            Check(PresenceEnvelope.Read(Frame("hello", "{\"service\":\"neura-api\"}"), out json) == PresenceFrameKind.Ignored, "Hello ignored.");
            Check(PresenceEnvelope.Read(Frame("error", "{\"message\":\"x\"}"), out json) == PresenceFrameKind.Ignored, "Error ignored.");
        }

        private static void RejectsMalformed()
        {
            string json;
            string good = Frame("avatar_presence", Snapshot);
            foreach (string bad in new[] {
                null, "", "{}", good.Replace("\"v\":1", "\"v\":2"), good.Substring(0, good.Length - 1),
                good.Replace(Id, Id.ToUpperInvariant()), good.Replace(Id, Id.Substring(1)),
                good.Replace("\"data\":{", "\"data\":["), good.Replace("avatar_presence", "Avatar_presence"),
                Frame("avatar_presence", Snapshot + new string(' ', PresenceEnvelope.MaxFrameCharacters)),
                " " + good
            })
                Check(PresenceEnvelope.Read(bad, out json) == PresenceFrameKind.Invalid && json == null, "Accepted malformed frame: " + bad);
        }

        private static void FrameDrivesSession()
        {
            var session = new PresentationSession();
            string json;
            Check(PresenceEnvelope.Read(Frame("avatar_presence", Snapshot), out json) == PresenceFrameKind.Presence, "Presence.");
            Check(session.Accept(json), "Relay snapshot accepted by the strict parser: " + session.LastError);
            Check(session.Current.Phase == "thinking" && session.Current.Motion == "subtle" && !session.Current.SafeMode, "Live state applied.");
            Check(PresenceEnvelope.Read(Frame("avatar_presence_cleared", "{\"reason\":\"no_publisher\"}"), out json) == PresenceFrameKind.Cleared, "Cleared.");
            session.Reset();
            Check(session.Current.SafeMode && session.Current.Motion == "still", "Cleared returns to safe Still.");
        }

        private static void PrivateFieldRejected()
        {
            var session = new PresentationSession();
            session.Accept(Snapshot);
            string json;
            string leaked = Snapshot.Insert(1, "\"journal\":\"private\",");
            Check(PresenceEnvelope.Read(Frame("avatar_presence", leaked), out json) == PresenceFrameKind.Presence, "Envelope is layout-only.");
            Check(!session.Accept(json), "Private field must be rejected.");
            Check(session.Current.SafeMode, "Rejection clears the animated state.");
        }
    }
}
