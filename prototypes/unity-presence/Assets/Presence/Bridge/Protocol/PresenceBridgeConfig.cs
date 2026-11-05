using System;

namespace Neura.Presence.Bridge
{
    public enum PresenceBridgeConfigError { None, Disabled, InvalidAddress, InvalidToken }

    // Launcher-supplied relay settings. Both values come only from this
    // process's environment, set by tools/Start-NeuraPresenceBridge.ps1 for
    // its child processes. Nothing is read from files, saved preferences, URLs or
    // the command line, and nothing is persisted.
    public sealed class PresenceBridgeConfig
    {
        public const string AddressVariable = "NEURA_PRESENCE_RELAY_ADDR";
        public const string TokenVariable = "NEURA_PRESENCE_TOKEN";

        private PresenceBridgeConfig(Uri endpoint, string token)
        {
            Endpoint = endpoint;
            Token = token;
        }

        public Uri Endpoint { get; private set; }

        // Internal: only the relay client in this assembly sends it.
        internal string Token { get; private set; }

        // Never includes the credential.
        public override string ToString() { return "PresenceBridgeConfig(" + Endpoint + ")"; }

        public static bool TryCreate(Func<string, string> read, out PresenceBridgeConfig config,
            out PresenceBridgeConfigError error)
        {
            config = null;
            string address = read == null ? null : read(AddressVariable);
            string token = read == null ? null : read(TokenVariable);
            if (string.IsNullOrEmpty(address) && string.IsNullOrEmpty(token))
            {
                error = PresenceBridgeConfigError.Disabled;
                return false;
            }
            Uri endpoint;
            if (!TryLoopbackEndpoint(address, out endpoint))
            {
                error = PresenceBridgeConfigError.InvalidAddress;
                return false;
            }
            if (!IsSessionToken(token))
            {
                error = PresenceBridgeConfigError.InvalidToken;
                return false;
            }
            config = new PresenceBridgeConfig(endpoint, token);
            error = PresenceBridgeConfigError.None;
            return true;
        }

        // Matches neura_api: exactly 64 hexadecimal characters.
        public static bool IsSessionToken(string token)
        {
            if (token == null || token.Length != 64) return false;
            foreach (char c in token)
            {
                bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
                if (!hex) return false;
            }
            return true;
        }

        // Numeric loopback only ("127.x.y.z:port" or "[::1]:port"). No host
        // names, so no DNS lookup can redirect the credential off-machine.
        public static bool TryLoopbackEndpoint(string address, out Uri endpoint)
        {
            endpoint = null;
            if (address == null || address.Length > 32) return false;
            int colon = address.LastIndexOf(':');
            if (colon <= 0) return false;
            string host = address.Substring(0, colon);
            int port;
            if (!TryPort(address.Substring(colon + 1), out port)) return false;
            if (host != "[::1]" && !IsIPv4Loopback(host)) return false;
            endpoint = new Uri("ws://" + host + ":" + port + "/");
            return true;
        }

        private static bool TryPort(string text, out int port)
        {
            port = 0;
            if (text.Length == 0 || text.Length > 5 || text[0] == '0') return false;
            foreach (char c in text)
            {
                if (c < '0' || c > '9') return false;
                port = port * 10 + (c - '0');
            }
            return port <= 65535;
        }

        private static bool IsIPv4Loopback(string host)
        {
            string[] parts = host.Split('.');
            if (parts.Length != 4 || parts[0] != "127") return false;
            foreach (string part in parts)
            {
                if (part.Length == 0 || part.Length > 3 || (part.Length > 1 && part[0] == '0')) return false;
                int value = 0;
                foreach (char c in part)
                {
                    if (c < '0' || c > '9') return false;
                    value = value * 10 + (c - '0');
                }
                if (value > 255) return false;
            }
            return true;
        }
    }
}
