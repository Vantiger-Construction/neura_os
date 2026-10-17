using NUnit.Framework;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Neura.Presence.Tests
{
    public sealed class ContractTests
    {
        [TestCaseSource(typeof(ContractCases), nameof(ContractCases.Names))]
        public void ContractScenario(string name) { ContractCases.Run(name); }

        [Test]
        public void BootstrapSceneAndShaderArePresent()
        {
            Assert.IsNotNull(Resources.Load<Shader>("NeuraPresence"));
            var scene = EditorSceneManager.OpenScene("Assets/Presence/Scenes/PresenceStage.unity", OpenSceneMode.Additive);
            try
            {
                var roots = scene.GetRootGameObjects();
                Assert.AreEqual(1, roots.Length);
                Assert.IsNotNull(roots[0].GetComponent<PresencePrototype>());
            }
            finally { EditorSceneManager.CloseScene(scene, true); }
        }
    }
}
