namespace Neura.Presence
{
    // Fail closed on invalid input and lifecycle changes. No background queue.
    public sealed class PresentationSession
    {
        public AvatarSnapshot Current { get; private set; } = AvatarSnapshot.SafeDefault();
        public SnapshotError LastError { get; private set; }
        public bool LocalSafeMode { get; private set; }

        public bool Accept(string json)
        {
            AvatarSnapshot next;
            SnapshotError error;
            bool valid = AvatarSnapshot.TryParse(json, out next, out error);
            LastError = error;
            Current = valid && !LocalSafeMode ? next : AvatarSnapshot.SafeDefault();
            return valid;
        }

        public void SetLocalSafeMode(bool value)
        {
            LocalSafeMode = value;
            Reset(); // Releasing the override requires a fresh valid snapshot.
        }

        public void Reset()
        {
            Current = AvatarSnapshot.SafeDefault();
            LastError = SnapshotError.None;
        }
    }
}
