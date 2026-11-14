using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Neura.Presence.Tests
{
    public sealed class StageTests
    {
        private GameObject root;
        private PresencePrototype stage;
        private const string Suite = "{\"v\":2,\"room_id\":\"her_suite\",\"phase\":\"idle\",\"stance\":\"welcoming\",\"motion\":\"subtle\",\"scale\":\"standard\",\"safe_mode\":false,\"lighting\":\"gold\",\"camera\":\"follow\",\"activity\":\"present\"}";
        private const string Animated = "{\"v\":1,\"room_id\":\"joy_lounge\",\"phase\":\"speaking\",\"stance\":\"playful\",\"motion\":\"expressive\",\"scale\":\"large\",\"safe_mode\":false}";

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            root = new GameObject("Test stage");
            stage = root.AddComponent<PresencePrototype>();
            yield return null;
            // Synthetic lifecycle input; native focus behavior remains a device gate.
            root.SendMessage("OnApplicationFocus", true);
        }
        [UnityTearDown]
        public IEnumerator TearDown() { Object.Destroy(root); yield return null; }

        [UnityTest]
        public IEnumerator MotionStaysOnItsOwnStandingAnchor()
        {
            var anchor = stage.StageAnchor.position;
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Animated));
            var firstScale = stage.VisualMount.localScale;
            yield return null;
            Assert.AreNotEqual(firstScale, stage.VisualMount.localScale);
            Assert.AreEqual(anchor, stage.StageAnchor.position);
            Assert.AreEqual(Vector3.zero, stage.VisualMount.localPosition);
            Assert.AreEqual("joy_lounge", stage.Current.RoomId);
        }
        [UnityTest]
        public IEnumerator SafeModeStopsImmediatelyAndStaysStill()
        {
            stage.ApplySyntheticSnapshot(Animated);
            yield return null;
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Animated.Replace("false", "true")));
            Assert.AreEqual("still", stage.Current.Motion);
            var scale = stage.VisualMount.localScale;
            var rotation = stage.VisualMount.localRotation;
            yield return null;
            yield return null;
            Assert.AreEqual(scale, stage.VisualMount.localScale);
            Assert.AreEqual(rotation, stage.VisualMount.localRotation);
        }
        [UnityTest]
        public IEnumerator HerSuiteShowsHerOwnSetOnlyInHerRoom()
        {
            Assert.IsFalse(stage.SuiteVisible);
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite));
            Assert.IsTrue(stage.SuiteVisible);
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Animated));
            Assert.IsFalse(stage.SuiteVisible);
            yield return null;
            Assert.AreEqual(0, root.GetComponentsInChildren<Collider>(true).Length);
        }
        [UnityTest]
        public IEnumerator RestingSitsLowerWithoutMovingTheAnchor()
        {
            var anchor = stage.StageAnchor.position;
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite));
            yield return null;
            float standing = stage.VisualMount.localScale.y;
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite.Replace("present", "resting")));
            yield return null;
            Assert.Less(stage.VisualMount.localScale.y, standing * 0.9f);
            Assert.AreEqual(anchor, stage.StageAnchor.position);
            Assert.AreEqual(Vector3.zero, stage.VisualMount.localPosition);
        }
        [UnityTest]
        public IEnumerator SafeModeInHerSuiteStandsHerUpAtOnce()
        {
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite.Replace("present", "resting")));
            yield return null;
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite.Replace("present", "resting").Replace("false", "true")));
            Assert.IsFalse(stage.Current.Resting);
            Assert.AreEqual(1f, stage.VisualMount.localScale.y / stage.VisualMount.localScale.x, 0.0001f);
        }
        [UnityTest]
        public IEnumerator FaceToFaceMovesTheCameraCloser()
        {
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite));
            for (int i = 0; i < 90; i++) yield return null;
            var cam = stage.StageCamera;
            var followPosition = cam.transform.localPosition;
            var followRotation = cam.transform.localRotation;
            float followFov = cam.fieldOfView;
            Assert.IsTrue(stage.ApplySyntheticSnapshot(Suite.Replace("follow", "face")));
            for (int i = 0; i < 90; i++) yield return null;
            Assert.Less(Mathf.Abs(cam.transform.localPosition.z), Mathf.Abs(followPosition.z) - 1f);
            Assert.Less(cam.fieldOfView, followFov);
            // Suspending snaps the whole framing back at once: position,
            // aim and field of view, not just the distance.
            stage.SuspendPresentation();
            Assert.Less(Vector3.Distance(followPosition, cam.transform.localPosition), 0.01f);
            Assert.Less(Quaternion.Angle(followRotation, cam.transform.localRotation), 0.1f);
            Assert.AreEqual(followFov, cam.fieldOfView, 0.01f);
        }
        [UnityTest]
        public IEnumerator InvalidInputClearsPreviousMotion()
        {
            stage.ApplySyntheticSnapshot(Animated);
            yield return null;
            Assert.IsFalse(stage.ApplySyntheticSnapshot(Animated.Replace("\"v\":1", "\"v\":2")));
            Assert.IsTrue(stage.Current.SafeMode);
            Assert.AreEqual("still", stage.Current.Motion);
        }
        [UnityTest]
        public IEnumerator FocusPauseAndDisableRequireFreshInput()
        {
            stage.ApplySyntheticSnapshot(Animated);
            root.SendMessage("OnApplicationFocus", false);
            Assert.IsFalse(stage.ApplySyntheticSnapshot(Animated));
            root.SendMessage("OnApplicationFocus", true);
            Assert.IsTrue(stage.Current.SafeMode);
            stage.ApplySyntheticSnapshot(Animated);
            root.SendMessage("OnApplicationPause", true);
            Assert.IsFalse(stage.ApplySyntheticSnapshot(Animated));
            root.SendMessage("OnApplicationPause", false);
            Assert.IsTrue(stage.Current.SafeMode);
            stage.ApplySyntheticSnapshot(Animated);
            stage.enabled = false;
            stage.enabled = true;
            yield return null;
            Assert.IsTrue(stage.Current.SafeMode);
        }
        [UnityTest]
        public IEnumerator GeneratedStageHasOnlyPassiveVisuals()
        {
            yield return null;
            Assert.AreEqual(0, root.GetComponentsInChildren<Collider>().Length);
            Assert.AreEqual(0, root.GetComponentsInChildren<Animator>().Length);
            Assert.AreEqual(1, root.GetComponentsInChildren<MonoBehaviour>().Length);
            Assert.AreEqual(1, root.GetComponentsInChildren<Camera>().Length);
            Assert.Greater(root.GetComponentsInChildren<MeshRenderer>().Length, 4);
        }

        [UnityTest]
        public IEnumerator RemovingHarnessCleansUpItsOwnedStage()
        {
            Object.Destroy(stage);
            yield return null;
            yield return null;
            Assert.AreEqual(0, root.transform.childCount);
        }
    }
}
