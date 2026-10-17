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
