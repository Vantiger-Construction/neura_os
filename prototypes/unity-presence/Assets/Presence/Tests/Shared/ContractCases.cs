using System;
using System.Collections.Generic;

namespace Neura.Presence.Tests
{
    // Identical core scenarios run in the console harness and Unity EditMode.
    public static class ContractCases
    {
        private const string Valid = "{\"v\":1,\"room_id\":\"penthouse\",\"phase\":\"idle\",\"stance\":\"welcoming\",\"motion\":\"expressive\",\"scale\":\"standard\",\"safe_mode\":false}";
        private static readonly Dictionary<string, Action> Cases = new Dictionary<string, Action>
        {
            { "producer_domain_matrix", ProducerDomainMatrix },
            { "field_order_and_whitespace", () => Accept(" { \n\"safe_mode\" : false, \"scale\":\"standard\", \"motion\":\"subtle\", \"stance\":\"welcoming\", \"phase\":\"idle\", \"room_id\":\"penthouse\", \"v\":1 } \t") },
            { "unsupported_versions", () => { Reject(Valid.Replace("\"v\":1", "\"v\":2"), SnapshotError.UnsupportedVersion); Reject(Valid.Replace("\"v\":1", "\"v\":0"), SnapshotError.UnsupportedVersion); } },
            { "missing_fields", MissingFields },
            { "duplicate_fields", () => Reject(Valid.Replace("\"v\":1", "\"v\":1,\"v\":1"), SnapshotError.DuplicateField) },
            { "private_and_unknown_fields", () => { foreach (string key in new[] { "prompt", "journal", "credential", "memory", "action", "text" }) Reject(Valid.Insert(1, "\"" + key + "\":\"synthetic\","), SnapshotError.UnknownField); } },
            { "wrong_json_types", WrongTypes },
            { "malformed_and_nested_json", Malformed },
            { "oversize_and_empty", () => { Reject(new string(' ', 513), SnapshotError.PayloadTooLarge); Reject(null); Reject(""); Reject("{}"); } },
            { "unknown_values", UnknownValues },
            { "escaped_and_non_ascii_tokens", () => { Reject(Valid.Replace("penthouse", "pent\\u0068ouse")); Reject(Valid.Replace("penthouse", "penthousé")); } },
            { "safe_flag_forces_still", () => RequireSafe(Accept(Valid.Replace("false", "true"))) },
            { "safe_phase_forces_still", () => RequireSafe(Accept(Valid.Replace("idle", "safeMode"))) },
            { "safe_input_still_requires_valid_structure", () => Reject(Valid.Replace("false", "true").Replace("expressive", "run")) },
            { "session_starts_safe", () => RequireSafe(new PresentationSession().Current) },
            { "rejection_clears_animated_state", RejectionClearsState },
            { "local_override_survives_incoming_states", LocalOverride },
            { "release_requires_fresh_snapshot", FreshAfterRelease },
            { "suspension_requires_fresh_snapshot", FreshAfterReset },
            { "still_and_safe_poses_are_time_invariant", StillPose },
            { "motion_and_scale_are_bounded", BoundedPose },
            { "nonfinite_time_is_still", NonfiniteTime }
        };

        public static IEnumerable<string> Names { get { return Cases.Keys; } }
        public static void Run(string name) { Cases[name](); }
        private static void Check(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }
        private static AvatarSnapshot Accept(string json)
        {
            AvatarSnapshot state;
            SnapshotError error;
            Check(AvatarSnapshot.TryParse(json, out state, out error), "Expected accepted synthetic snapshot: " + error);
            Check(error == SnapshotError.None && state != null, "Accepted state missing.");
            return state;
        }
        private static void Reject(string json, SnapshotError? expected = null)
        {
            AvatarSnapshot state;
            SnapshotError error;
            Check(!AvatarSnapshot.TryParse(json, out state, out error), "Invalid snapshot was accepted.");
            Check(state == null && error != SnapshotError.None, "Rejection leaked a state.");
            if (expected.HasValue) Check(error == expected.Value, "Unexpected rejection category: " + error);
        }
        private static void RequireSafe(AvatarSnapshot state)
        {
            Check(state.SafeMode && state.Phase == "safeMode" && state.Motion == "still", "Safe Mode must force Still.");
        }
        private static void ProducerDomainMatrix()
        {
            string[] rooms = { "penthouse", "reflection_bay", "joy_lounge", "mood_den", "dream_atrium", "legacy_vault" };
            string[] stances = { "welcoming", "reflective", "playful", "grounding", "dreaming", "guardian" };
            for (int i = 0; i < rooms.Length; i++)
            foreach (string phase in new[] { "idle", "thinking", "speaking", "listening", "safeMode" })
            foreach (string motion in new[] { "still", "subtle", "expressive" })
            foreach (string scale in new[] { "compact", "standard", "large" })
            {
                var state = Accept(Valid.Replace("penthouse", rooms[i]).Replace("welcoming", stances[i])
                    .Replace("idle", phase).Replace("expressive", motion).Replace("standard", scale));
                Check(state.RoomId == rooms[i] && state.Stance == stances[i] && state.Scale == scale, "Lost presentation data.");
                if (phase == "safeMode") RequireSafe(state);
                else Check(state.Motion == motion && state.Phase == phase && !state.SafeMode, "Changed an ordinary state.");
            }
        }
        private static void MissingFields()
        {
            foreach (string member in new[] { "\"v\":1,", "\"room_id\":\"penthouse\",", "\"phase\":\"idle\",",
                "\"stance\":\"welcoming\",", "\"motion\":\"expressive\",", "\"scale\":\"standard\",", ",\"safe_mode\":false" })
                Reject(Valid.Replace(member, ""), SnapshotError.MissingField);
        }
        private static void WrongTypes()
        {
            foreach (string version in new[] { "\"1\"", "1.0", "1e0", "true", "null", "01", "-1" })
                Reject(Valid.Replace("\"v\":1", "\"v\":" + version));
            foreach (string boolean in new[] { "\"false\"", "0", "null", "False", "falsex" })
                Reject(Valid.Replace("false", boolean));
            Reject(Valid.Replace("\"idle\"", "null"));
        }
        private static void Malformed()
        {
            foreach (string bad in new[] { Valid + "{}", "[" + Valid + "]", Valid.Substring(0, Valid.Length - 1),
                Valid.Replace("\"idle\"", "{}"), Valid.Replace("\"idle\"", "[]"), Valid.Replace("\"v\":1", "\"v\":1,"),
                Valid.Replace("\"room_id\":", "room_id:"), Valid.Replace("\"idle\"", "\"id\nle\""), Valid.Replace("false}", "false,}") })
                Reject(bad);
        }
        private static void UnknownValues()
        {
            foreach (string value in new[] { "penthouse", "idle", "welcoming", "expressive", "standard" })
            {
                Reject(Valid.Replace(value, "unsupported"), SnapshotError.InvalidValue);
                Reject(Valid.Replace(value, value.ToUpperInvariant()), SnapshotError.InvalidValue);
            }
        }
        private static void RejectionClearsState()
        {
            var session = new PresentationSession();
            Check(session.Accept(Valid) && session.Current.Motion == "expressive", "Animated setup failed.");
            Check(!session.Accept(Valid.Replace("\"v\":1", "\"v\":99")), "Unsupported version accepted.");
            RequireSafe(session.Current);
            Check(session.LastError == SnapshotError.UnsupportedVersion, "Error category lost.");
        }
        private static void LocalOverride()
        {
            var session = new PresentationSession();
            session.SetLocalSafeMode(true);
            Check(session.Accept(Valid), "Valid synthetic input rejected.");
            RequireSafe(session.Current);
            session.Accept("invalid");
            session.Reset();
            Check(session.LocalSafeMode, "Reset released the safety override.");
            RequireSafe(session.Current);
        }
        private static void FreshAfterRelease()
        {
            var session = new PresentationSession();
            session.Accept(Valid);
            session.SetLocalSafeMode(true);
            session.SetLocalSafeMode(false);
            RequireSafe(session.Current);
            Check(session.Accept(Valid) && !session.Current.SafeMode, "Fresh state cannot resume.");
        }
        private static void FreshAfterReset()
        {
            var session = new PresentationSession();
            session.Accept(Valid);
            session.Reset();
            RequireSafe(session.Current);
            Check(session.Accept(Valid) && !session.Current.SafeMode, "Fresh state cannot resume.");
        }
        private static void StillPose()
        {
            foreach (var state in new[] { AvatarSnapshot.SafeDefault(), Accept(Valid.Replace("expressive", "still")) })
            {
                var a = PresentationPose.Evaluate(state, 0);
                var b = PresentationPose.Evaluate(state, 1234.5);
                Check(a.HeightMultiplier == 1 && b.HeightMultiplier == 1 && a.YawDegrees == b.YawDegrees, "Still pose moved.");
            }
        }
        private static void BoundedPose()
        {
            foreach (string scale in new[] { "compact", "standard", "large" })
            foreach (string motion in new[] { "subtle", "expressive" })
            {
                var state = Accept(Valid.Replace("standard", scale).Replace("expressive", motion));
                bool changed = false;
                for (int i = 0; i < 1000; i++)
                {
                    var pose = PresentationPose.Evaluate(state, i * 0.137);
                    Check(pose.Scale >= 0.8f && pose.Scale <= 1.15f, "Stage scale out of bounds.");
                    Check(pose.HeightMultiplier >= 0.98f && pose.HeightMultiplier <= 1.02f, "Breathing exceeded its bounds.");
                    Check(Math.Abs(pose.YawDegrees) <= 5, "Motion exceeded its bounds.");
                    changed |= pose.HeightMultiplier != 1;
                }
                Check(changed, "Animated mode never moved.");
            }
        }
        private static void NonfiniteTime()
        {
            foreach (double time in new[] { double.NaN, double.PositiveInfinity, double.NegativeInfinity })
            {
                var pose = PresentationPose.Evaluate(Accept(Valid), time);
                Check(pose.HeightMultiplier == 1 && pose.YawDegrees == 0, "Invalid clock reached transforms.");
            }
        }
    }
}
