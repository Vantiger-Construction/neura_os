using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Neura.Presence.Bridge
{
    public enum PresenceLinkState { Stopped, Connecting, Connected, Waiting }

    // Subscribes to the neura_api presence relay on a background task. The
    // main thread only ever sees the most recent frame (a latest-only
    // mailbox) and a connection epoch that changes on every connect or drop,
    // so any link change can be turned into a safe Still presentation before
    // a fresh snapshot is shown. No frame history is kept.
    public sealed class PresenceRelayClient : IDisposable
    {
        public const int MaxMessageBytes = 4096;
        private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(5);
        private static readonly TimeSpan MaxBackoff = TimeSpan.FromSeconds(30);

        private readonly PresenceBridgeConfig config;
        private readonly CancellationTokenSource stop = new CancellationTokenSource();
        private readonly SemaphoreSlim resync = new SemaphoreSlim(0, 1);
        private string latest;
        private int epoch;
        private int state = (int)PresenceLinkState.Stopped;
        private CancellationTokenSource current;
        private Task loop;

        public PresenceRelayClient(PresenceBridgeConfig config)
        {
            if (config == null) throw new ArgumentNullException("config");
            this.config = config;
        }

        public PresenceLinkState State { get { return (PresenceLinkState)Volatile.Read(ref state); } }
        public int ConnectionEpoch { get { return Volatile.Read(ref epoch); } }

        public void Start()
        {
            if (loop != null || stop.IsCancellationRequested) return;
            loop = Task.Run(() => RunAsync(stop.Token));
        }

        // Takes and clears the most recent frame, or null.
        public string TakeLatestFrame() { return Interlocked.Exchange(ref latest, null); }

        // Asks the relay to resend the current state on this connection.
        public void RequestResync()
        {
            try { resync.Release(); }
            catch (SemaphoreFullException) { /* A resync is already pending; one is enough. */ }
            catch (ObjectDisposedException) { /* Client disposed; nothing to resync. */ }
        }

        // Drops the current connection (for a hung link); the loop reconnects.
        public void Reconnect()
        {
            var link = Volatile.Read(ref current);
            if (link == null) return;
            try { link.Cancel(); }
            catch (ObjectDisposedException) { /* That connection already ended; the loop is reconnecting. */ }
        }

        public void Dispose()
        {
            if (stop.IsCancellationRequested) return;
            stop.Cancel();
            Interlocked.Exchange(ref latest, null);
            Volatile.Write(ref state, (int)PresenceLinkState.Stopped);
        }

        private async Task RunAsync(CancellationToken token)
        {
            TimeSpan backoff = TimeSpan.FromSeconds(1);
            while (!token.IsCancellationRequested)
            {
                bool connected = false;
                using (var link = CancellationTokenSource.CreateLinkedTokenSource(token))
                using (var socket = new ClientWebSocket())
                {
                    Volatile.Write(ref current, link);
                    try
                    {
                        Volatile.Write(ref state, (int)PresenceLinkState.Connecting);
                        socket.Options.SetRequestHeader("Authorization", "Bearer " + config.Token);
                        using (var connectLimit = CancellationTokenSource.CreateLinkedTokenSource(link.Token))
                        {
                            connectLimit.CancelAfter(ConnectTimeout);
                            await socket.ConnectAsync(config.Endpoint, connectLimit.Token).ConfigureAwait(false);
                        }
                        connected = true;
                        backoff = TimeSpan.FromSeconds(1);
                        Interlocked.Increment(ref epoch);
                        Volatile.Write(ref state, (int)PresenceLinkState.Connected);
                        // Drain a resync requested while disconnected; the
                        // subscribe below already delivers the current state.
                        while (resync.Wait(0)) { }
                        await SendAsync(socket, link.Token).ConfigureAwait(false);
                        Task pump = PumpResyncAsync(socket, link.Token);
                        await ReceiveAsync(socket, link.Token).ConfigureAwait(false);
                        link.Cancel();
                        try { await pump.ConfigureAwait(false); }
                        catch (OperationCanceledException) { /* Expected: the pump stops with the link. */ }
                    }
                    // Every failure ends this connection the same way: the finally
                    // block bumps the epoch (the bridge shows safe Still) and the
                    // loop reconnects with backoff. No detail is surfaced, so
                    // nothing about the endpoint or credential can leak.
                    catch (OperationCanceledException) { /* Stopped, reconnect requested, or connect timeout. */ }
                    catch (WebSocketException) { /* Refused (including a bad token) or dropped. */ }
                    catch (InvalidOperationException) { /* Connection closed mid-operation. */ }
                    finally
                    {
                        Volatile.Write(ref current, null);
                        Interlocked.Exchange(ref latest, null);
                        if (connected) Interlocked.Increment(ref epoch);
                        if (!token.IsCancellationRequested)
                            Volatile.Write(ref state, (int)PresenceLinkState.Waiting);
                        socket.Abort();
                    }
                }
                if (token.IsCancellationRequested) break;
                try { await Task.Delay(backoff, token).ConfigureAwait(false); }
                catch (OperationCanceledException) { break; }
                backoff = TimeSpan.FromTicks(Math.Min(backoff.Ticks * 2, MaxBackoff.Ticks));
            }
        }

        private async Task PumpResyncAsync(ClientWebSocket socket, CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                await resync.WaitAsync(token).ConfigureAwait(false);
                await SendAsync(socket, token).ConfigureAwait(false);
            }
        }

        private static Task SendAsync(ClientWebSocket socket, CancellationToken token)
        {
            byte[] bytes = Encoding.ASCII.GetBytes(PresenceEnvelope.SubscribeMessage);
            return socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, token);
        }

        private async Task ReceiveAsync(ClientWebSocket socket, CancellationToken token)
        {
            var buffer = new byte[MaxMessageBytes];
            while (!token.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                int count = 0;
                WebSocketReceiveResult result;
                do
                {
                    if (count == buffer.Length) return; // Oversized: drop the link.
                    result = await socket.ReceiveAsync(
                        new ArraySegment<byte>(buffer, count, buffer.Length - count), token).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close) return;
                    count += result.Count;
                } while (!result.EndOfMessage);
                if (result.MessageType != WebSocketMessageType.Text) return;
                Interlocked.Exchange(ref latest, Encoding.UTF8.GetString(buffer, 0, count));
            }
        }
    }
}
