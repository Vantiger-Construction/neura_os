The runtime approval lifecycle tests use DateTime.now().toUtc() for status assertions so the bounded lease is active relative to the executing test clock.
