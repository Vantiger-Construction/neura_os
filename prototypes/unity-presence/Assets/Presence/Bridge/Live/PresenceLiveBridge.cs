using System;
using UnityEngine;

namespace Neura.Presence.Bridge
{
    // Opt-in live input for the presence prototype. It attaches itself only
    // when the trusted launcher supplied NEURA_PRESENCE_RELAY_ADDR and
    // NEURA_PRESENCE_TOKEN; otherwise the prototype stays synthetic-only.
    //
    // Fail-closed rules: every connect, drop, cleared frame, invalid frame,
    // focus loss, pause, or 8 s without any frame returns the prototype to
    // safe Still. Motion resumes only on a fresh, strictly valid snapshot.
    [DisallowMultipleComponent]
    public sealed class PresenceLiveBridge : MonoBehaviour
    {
        // Above the relay's 2 s keepalive and 6 s staleness window.
        public const float SilenceLimitSeconds = 8f;

        private PresencePrototype target;
        private PresenceRelayClient client;
        private string lastApplied;
        private float lastFrameAt;
        private int seenEpoch;
        private bool live;

        public string Status { get; private set; }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void AttachIfLaunched()
        {
            PresenceBridgeConfig config;
            PresenceBridgeConfigError error;
            bool valid = PresenceBridgeConfig.TryCreate(Environment.GetEnvironmentVariable, out config, out error);
            if (!valid && error == PresenceBridgeConfigError.Disabled) return;
            var prototype = FindFirstObjectByType<PresencePrototype>();
            if (prototype == null) return;
            var bridge = prototype.gameObject.AddComponent<PresenceLiveBridge>();
            bridge.Begin(prototype, valid ? config : null, error);
        }

        private void Begin(PresencePrototype prototype, PresenceBridgeConfig config, PresenceBridgeConfigError error)
        {
            target = prototype;
            if (config == null)
            {
                Status = error == PresenceBridgeConfigError.InvalidToken
                    ? "Live bridge: invalid launcher token"
                    : "Live bridge: invalid relay address";
                return;
            }
            client = new PresenceRelayClient(config);
            seenEpoch = client.ConnectionEpoch;
            Status = "Live bridge: connecting";
            client.Start();
        }

        private void Update()
        {
            if (client == null || target == null) return;

            int epoch = client.ConnectionEpoch;
            if (epoch != seenEpoch)
            {
                seenEpoch = epoch;
                Withdraw();
            }

            string frame = client.TakeLatestFrame();
            if (frame != null)
            {
                lastFrameAt = Time.unscaledTime;
                string snapshot;
                switch (PresenceEnvelope.Read(frame, out snapshot))
                {
                    case PresenceFrameKind.Presence:
                        live = true;
                        // Keepalive repeats are not re-applied, so motion
                        // continues smoothly instead of restarting.
                        if (snapshot != lastApplied)
                            lastApplied = target.ApplyLiveSnapshot(snapshot) ? snapshot : null;
                        break;
                    case PresenceFrameKind.Cleared:
                    case PresenceFrameKind.Invalid:
                        Withdraw();
                        break;
                }
            }
            else if (live && Time.unscaledTime - lastFrameAt > SilenceLimitSeconds)
            {
                Withdraw();
                client.Reconnect();
            }

            Status = client.State != PresenceLinkState.Connected ? "Live bridge: reconnecting"
                : live && lastApplied != null ? "Live bridge: live"
                : "Live bridge: waiting for Neura";
        }

        private void OnApplicationFocus(bool value) { Interrupted(!value); }
        private void OnApplicationPause(bool value) { Interrupted(value); }

        private void Interrupted(bool suspended)
        {
            // The prototype suspends itself; forget what it showed so the
            // next valid snapshot is applied, and ask for one on return.
            lastApplied = null;
            if (!suspended && client != null) client.RequestResync();
        }

        private void Withdraw()
        {
            lastApplied = null;
            live = false;
            if (target != null) target.SuspendPresentation();
        }

        private void OnDisable() { Withdraw(); }

        private void OnDestroy()
        {
            if (client != null) client.Dispose();
            client = null;
        }

        private void OnGUI()
        {
            if (string.IsNullOrEmpty(Status)) return;
            GUI.Label(new Rect(Screen.width - 280, Screen.height - 28, 270, 22), Status);
        }
    }
}
