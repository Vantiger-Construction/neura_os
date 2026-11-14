using System;
using System.Collections.Generic;
using System.Linq;

namespace Neura.Presence.Tests
{
    // Identical core scenarios run in the console harness and Unity EditMode.
    public static class ContractCases
    {
        private const string Valid = "{\"v\":1,\"room_id\":\"penthouse\",\"phase\":\"idle\",\"stance\":\"welcoming\",\"motion\":\"expressive\",\"scale\":\"standard\",\"safe_mode\":false}";
        private const string ValidV2 = "{\"v\":2,\"room_id\":\"her_suite\",\"phase\":\"idle\",\"stance\":\"welcoming\",\"motion\":\"subtle\",\"scale\":\"standard\",\"safe_mode\":false,\"lighting\":\"gold\",\"camera\":\"follow\",\"activity\":\"resting\"}";
        private static readonly Dictionary<string, Action> Cases = new Dictionary<string, Action>
        {
            { "v2_domain_matrix", V2DomainMatrix },
            { "v1_reads_as_standard_stage", V1StandardStage },
            { "v1_cannot_name_her_suite_or_stage_fields", V1Boundaries },
            { "v2_requires_every_stage_field", V2RequiresStage },
            { "v2_unknown_stage_values", () => { Reject(ValidV2.Replace("gold", "neon"), SnapshotError.InvalidValue); Reject(ValidV2.Replace("follow", "orbit"), SnapshotError.InvalidValue); Reject(ValidV2.Replace("resting", "sleeping"), SnapshotError.InvalidValue); } },
            { "v2_safe_mode_forces_present_still", V2SafeMode },
            { "suite_lighting_moods_are_distinct", SuiteLighting },
            { "standard_lighting_keeps_room_accents", StandardLighting },
            { "camera_framings_are_distinct_and_bounded", CameraFraming },
            { "resting_sits_lower_and_breathes_slowly", RestingPose },
            { "safe_mode_stands_her_up_from_rest", SafeStandsUp },
            { "producer_domain_matrix", ProducerDomainMatrix },
            { "field_order_and_whitespace", () => Accept(" { \n\"safe_mode\" : false, \"scale\":\"standard\", \"motion\":\"subtle\", \"stance\":\"welcoming\", \"phase\":\"idle\", \"room_id\":\"penthouse\", \"v\":1 } \t") },
            { "unsupported_versions", () => { Reject(Valid.Replace("\"v\":1", "\"v\":3"), SnapshotError.UnsupportedVersion); Reject(Valid.Replace("\"v\":1", "\"v\":0"), SnapshotError.UnsupportedVersion); Reject(ValidV2.Replace("\"v\":2", "\"v\":3"), SnapshotError.UnsupportedVersion); } },
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
        // Tight absolute tolerance for the bounded, unit-scale presentation values.
        // NaN and infinities fail this comparison rather than passing silently.
        private static bool Near(float actual, float expected)
        {
            return Math.Abs(actual - expected) <= 0.000001f;
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
        private static void V2DomainMatrix()
        {
            foreach (string room in new[] { "penthouse", "reflection_bay", "joy_lounge", "mood_den", "dream_atrium", "legacy_vault", "her_suite" })
            foreach (string lighting in new[] { "standard", "gold", "aurora", "dusk" })
            foreach (string camera in new[] { "follow", "wide", "face" })
            foreach (string activity in new[] { "present", "resting" })
            {
                string json = ValidV2.Replace("her_suite", room).Replace("gold", lighting)
                    .Replace("follow", camera).Replace("resting", activity);
                // Resting belongs to Her Suite; anywhere else it is rejected.
                if (activity == "resting" && room != "her_suite")
                {
                    Reject(json, SnapshotError.InvalidValue);
                    continue;
                }
                var state = Accept(json);
                Check(state.SourceVersion == 2 && state.RoomId == room && state.Lighting == lighting &&
                    state.Camera == camera && state.Activity == activity, "Lost v2 stage data.");
                Check(state.Resting == (activity == "resting"), "Resting flag mismatch.");
            }
        }
        private static void V1StandardStage()
        {
            var state = Accept(Valid);
            Check(state.SourceVersion == 1 && state.Lighting == "standard" && state.Camera == "follow" &&
                state.Activity == "present" && !state.Resting, "v1 must read as the standard stage.");
        }
        private static void V1Boundaries()
        {
            Reject(Valid.Replace("penthouse", "her_suite"), SnapshotError.InvalidValue);
            Reject(Valid.Insert(1, "\"lighting\":\"gold\","), SnapshotError.UnknownField);
            Reject(Valid.Insert(1, "\"activity\":\"resting\","), SnapshotError.UnknownField);
        }
        private static void V2RequiresStage()
        {
            Reject(ValidV2.Replace(",\"lighting\":\"gold\"", ""), SnapshotError.MissingField);
            Reject(ValidV2.Replace(",\"camera\":\"follow\"", ""), SnapshotError.MissingField);
            Reject(ValidV2.Replace(",\"activity\":\"resting\"", ""), SnapshotError.MissingField);
            Reject(ValidV2.Replace(",\"lighting\":\"gold\"", ",\"journal\":\"gold\""), SnapshotError.UnknownField);
        }
        private static void V2SafeMode()
        {
            var state = Accept(ValidV2.Replace("false", "true").Replace("subtle", "expressive"));
            RequireSafe(state);
            Check(state.Activity == "present" && !state.Resting, "Safe Mode must show the present pose.");
            Check(state.Lighting == "gold", "Safe Mode keeps the lighting choice.");
            RequireSafe(Accept(ValidV2.Replace("idle", "safeMode")));
        }
        private static AvatarSnapshot Suite(string lighting, string camera, string activity, string motion = "subtle")
        {
            return Accept(ValidV2.Replace("gold", lighting).Replace("follow", camera)
                .Replace("resting", activity).Replace("subtle", motion));
        }
        private static void SuiteLighting()
        {
            var gold = StagePalette.Evaluate(Suite("gold", "follow", "present"));
            var aurora = StagePalette.Evaluate(Suite("aurora", "follow", "present"));
            var dusk = StagePalette.Evaluate(Suite("dusk", "follow", "present"));
            var standard = StagePalette.Evaluate(Suite("standard", "follow", "present"));
            Check(!gold.Accent.Equals(aurora.Accent) && !aurora.Accent.Equals(dusk.Accent) &&
                !gold.Accent.Equals(dusk.Accent), "Lighting moods must differ.");
            Check(standard.Accent.Equals(gold.Accent) && standard.Wall.Equals(gold.Wall),
                "Her Suite's standard lighting is her gold hour.");
            foreach (var palette in new[] { gold, aurora, dusk })
                foreach (float c in new[] { palette.Accent.R, palette.Accent.G, palette.Accent.B,
                    palette.Background.R, palette.Wall.B })
                    Check(c >= 0f && c <= 1f, "Palette channel out of range.");
        }
        private static void StandardLighting()
        {
            string[] rooms = { "penthouse", "reflection_bay", "joy_lounge", "mood_den", "dream_atrium", "legacy_vault" };
            var seen = new HashSet<string>();
            foreach (string room in rooms)
            {
                var palette = StagePalette.Evaluate(Accept(Valid.Replace("penthouse", room)));
                Check(seen.Add(palette.Accent.R + "," + palette.Accent.G + "," + palette.Accent.B),
                    "Each room keeps its own accent: " + room);
            }
        }
        private static void CameraFraming()
        {
            var follow = StageFraming.Evaluate(Suite("gold", "follow", "present"));
            var wide = StageFraming.Evaluate(Suite("gold", "wide", "present"));
            var face = StageFraming.Evaluate(Suite("gold", "face", "present"));
            Check(Math.Abs(face.PositionZ) < Math.Abs(follow.PositionZ) &&
                Math.Abs(follow.PositionZ) < Math.Abs(wide.PositionZ), "Face is closest and wide is farthest.");
            Check(face.FieldOfView < follow.FieldOfView && follow.FieldOfView < wide.FieldOfView, "Field of view widens.");
            foreach (var f in new[] { follow, wide, face })
                Check(f.PositionZ < -1.5f && f.FieldOfView >= 20f && f.FieldOfView <= 60f &&
                    f.TargetY > 0.5f && f.TargetY < 1.7f, "Framing out of bounds.");
            var v1 = StageFraming.Evaluate(Accept(Valid));
            Check(Near(v1.PositionZ, follow.PositionZ) && Near(v1.FieldOfView, follow.FieldOfView), "v1 uses the follow camera.");
            var resting = StageFraming.Evaluate(Suite("gold", "face", "resting"));
            Check(resting.TargetY < face.TargetY, "The camera follows her down when she rests.");
        }
        private static void RestingPose()
        {
            var standing = Suite("gold", "follow", "present");
            var resting = Suite("gold", "follow", "resting");
            float lowest = float.MaxValue, highest = float.MinValue;
            for (int i = 0; i < 400; i++)
            {
                double t = i * 0.05;
                var pose = PresentationPose.Evaluate(resting, t);
                lowest = Math.Min(lowest, pose.HeightMultiplier);
                highest = Math.Max(highest, pose.HeightMultiplier);
                Check(pose.HeightMultiplier < PresentationPose.Evaluate(standing, t).HeightMultiplier,
                    "Resting sits lower than standing.");
                Check(pose.YawDegrees < -20f && pose.YawDegrees > -35f, "Resting faces the window.");
            }
            Check(highest - lowest < 0.02f && highest - lowest > 0f, "Resting only breathes slowly.");
            var stillRest = Suite("gold", "follow", "resting", "still");
            Check(Near(PresentationPose.Evaluate(stillRest, 0).HeightMultiplier,
                PresentationPose.Evaluate(stillRest, 3.7).HeightMultiplier), "Still resting is time invariant.");
        }
        private static void SafeStandsUp()
        {
            var state = Accept(ValidV2.Replace("false", "true"));
            var pose = PresentationPose.Evaluate(state, 1.3);
            Check(Near(pose.HeightMultiplier, 1f) && !state.Resting, "Safe Mode shows the standing, present pose.");
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
                Check(Near(a.HeightMultiplier, 1f) && Near(b.HeightMultiplier, 1f) && Near(a.YawDegrees, b.YawDegrees), "Still pose moved.");
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
                    changed |= !Near(pose.HeightMultiplier, 1f);
                }
                Check(changed, "Animated mode never moved.");
            }
        }
        private static void NonfiniteTime()
        {
            var state = Accept(Valid);
            foreach (var pose in new[] { double.NaN, double.PositiveInfinity, double.NegativeInfinity }
                .Select(time => PresentationPose.Evaluate(state, time)))
            {
                Check(Near(pose.HeightMultiplier, 1f) && Near(pose.YawDegrees, 0f), "Invalid clock reached transforms.");
            }
        }
    }
}
