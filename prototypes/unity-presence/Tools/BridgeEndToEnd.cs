using System;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Neura.Presence;
using Neura.Presence.Bridge;

// End-to-end check against a real neura_api started by run_bridge_e2e.sh with
// the presence relay enabled. Plays the Neura app (publisher) over a raw
// socket and uses the Unity bridge's own PresenceRelayClient as subscriber.
public static class BridgeEndToEnd
{
    private const string SnapshotV2 = "{\"v\":2,\"room_id\":\"her_suite\",\"phase\":\"idle\",\"stance\":\"welcoming\",\"motion\":\"subtle\",\"scale\":\"standard\",\"safe_mode\":false,\"lighting\":\"aurora\",\"camera\":\"face\",\"activity\":\"resting\"}";
    private const string Snapshot = "{\"v\":1,\"room_id\":\"reflection_bay\",\"phase\":\"{PHASE}\",\"stance\":\"reflective\",\"motion\":\"subtle\",\"scale\":\"standard\",\"safe_mode\":false}";

    public static int Main()
    {
        try
        {
            Run().GetAwaiter().GetResult();
            Console.WriteLine("Bridge end-to-end: PASS");
            return 0;
        }
        // Top-level harness reporter: any failure, of any type, must turn
        // into a FAIL line and a non-zero exit for CI.
        catch (Exception error)
        {
            Console.Error.WriteLine("Bridge end-to-end: FAIL " + error.Message);
            return 1;
        }
    }

    private static async Task Run()
    {
        PresenceBridgeConfig config;
        PresenceBridgeConfigError configError;
        Require(PresenceBridgeConfig.TryCreate(Environment.GetEnvironmentVariable, out config, out configError),
            "launcher config: " + configError);
        string token = Environment.GetEnvironmentVariable(PresenceBridgeConfig.TokenVariable);

        using (var unity = new PresenceRelayClient(config))
        {
            unity.Start();
            Require(Next(unity) == PresenceFrameKind.Cleared, "subscriber starts with no publisher");
            Console.WriteLine("PASS subscriber connected and saw no publisher");

            using (var app = await Connect(config.Endpoint, token))
            {
                await Publish(app, "thinking");
                var session = new PresentationSession();
                string json;
                Require(Next(unity, out json) == PresenceFrameKind.Presence, "presence delivered");
                Require(session.Accept(json) && session.Current.Phase == "thinking" && !session.Current.SafeMode,
                    "strict parser accepted relayed snapshot");
                Console.WriteLine("PASS app snapshot reached the Unity session");

                await Publish(app, "speaking");
                Require(Next(unity, out json) == PresenceFrameKind.Presence && session.Accept(json) &&
                    session.Current.Phase == "speaking", "change delivered");
                Console.WriteLine("PASS phase change delivered");

                await PublishData(app, SnapshotV2);
                Require(Next(unity, out json) == PresenceFrameKind.Presence && session.Accept(json) &&
                    session.Current.RoomId == "her_suite" && session.Current.Lighting == "aurora" &&
                    session.Current.Camera == "face" && session.Current.Resting, "v2 stage delivered");
                Console.WriteLine("PASS v2 Her Suite stage delivered");

                await Publish(app, "speaking");
                Require(Next(unity, out json) == PresenceFrameKind.Presence && session.Accept(json) &&
                    session.Current.SourceVersion == 1 && !session.Current.Resting, "v1 still accepted after v2");
                Console.WriteLine("PASS v1 still accepted after v2");

                unity.Reconnect();
                Require(Next(unity, out json) == PresenceFrameKind.Presence && session.Accept(json) &&
                    session.Current.Phase == "speaking", "current state resent after reconnect");
                Console.WriteLine("PASS reconnect resubscribes and receives current state");

                // neura_api drops a closing client without a close handshake.
                app.Abort();
            }
            Require(Next(unity) == PresenceFrameKind.Cleared, "publisher exit withdraws presence");
            Console.WriteLine("PASS publisher exit withdraws presence");
        }

        bool rejected = false;
        try { using (await Connect(config.Endpoint, new string('c', 64))) { } }
        catch (WebSocketException) { rejected = true; }
        Require(rejected, "wrong token refused");
        Console.WriteLine("PASS wrong session token refused");
    }

    private static PresenceFrameKind Next(PresenceRelayClient client)
    {
        string ignored;
        return Next(client, out ignored);
    }

    // Waits for the next presence or cleared frame (skipping replies).
    private static PresenceFrameKind Next(PresenceRelayClient client, out string json)
    {
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < TimeSpan.FromSeconds(10))
        {
            string frame = client.TakeLatestFrame();
            if (frame != null)
            {
                PresenceFrameKind kind = PresenceEnvelope.Read(frame, out json);
                if (kind != PresenceFrameKind.Ignored) return kind;
            }
            Thread.Sleep(20);
        }
        throw new InvalidOperationException("timed out waiting for a relay frame");
    }

    private static async Task<ClientWebSocket> Connect(Uri endpoint, string token)
    {
        var socket = new ClientWebSocket();
        socket.Options.SetRequestHeader("Authorization", "Bearer " + token);
        await socket.ConnectAsync(endpoint, CancellationToken.None);
        return socket;
    }

    private static Task Publish(ClientWebSocket socket, string phase)
    {
        return PublishData(socket, Snapshot.Replace("{PHASE}", phase));
    }

    private static Task PublishData(ClientWebSocket socket, string data)
    {
        string message = "{\"v\":1,\"kind\":\"presence_publish\",\"data\":" + data + "}";
        byte[] bytes = Encoding.ASCII.GetBytes(message);
        return socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
    }

    private static void Require(bool value, string what)
    {
        if (!value) throw new InvalidOperationException(what);
    }
}
