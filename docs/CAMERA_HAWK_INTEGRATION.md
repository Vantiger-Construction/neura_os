# Camera Hawk integration in Neura OS

This first Windows integration uses the user's Camera_Hawk_v3_7_Drone_Watch_Bundle.zip (September 13, 2026) source, specifically services/camera-api/main.py, neura_vision/api/auth_routes.py, and neura_vision/api/routes.py.

Open Neura's command palette and search for **Camera Hawk**. Start the existing Camera Hawk installation separately, listening on 127.0.0.1:8799, then enter its viewer account in Neura. Neura signs in with POST /v1/auth/login, reads GET /v1/vision/cameras, and revokes with POST /v1/auth/logout. Only camera names, locations and enabled flags enter Neura's UI; source URLs and vault references are discarded.

**Open camera dashboard** opens http://127.0.0.1:8799/ in the system browser. Sign in there separately for live viewing and the existing Camera Hawk controls. No token or password is placed in the URL. The browser and independent Camera Hawk service have their own lifecycle: Neura Safe Mode does not stop them. Close the browser separately when finished.

## Boundaries

- No startup connection, periodic polling, automatic service installation/startup, discovery, media fetching, recording changes, PTZ or drone control from Neura.
- The Neura viewer session is RAM-only. Password fields clear after submission; tokens never enter preferences, journal, chat, memory or logs.
- Screen closure, backgrounding, Safe Mode and recovery immediately discard Neura's authorization and camera list. Logout is best effort if Camera Hawk is offline; its server still controls expiry.
- A late sign-in is revoked instead of restoring a disconnected session. Late list responses are discarded.
- Requests use a fixed numeric loopback endpoint, refuse redirects, time out and bound JSON response size.
- Windows only for this slice. Android cannot use a Windows PC through its own loopback address; authenticated remote transport and physical-device validation remain future work.
- Camera Hawk backend, media relay and recording remain separate installations. This PR does not bundle binaries or alter the source package.

## Validation

Seven HTTP/session tests passed under standalone Dart package:test using the same test bodies committed with flutter_test. Client/test analysis passed. Flutter widget lifecycle tests are included for Safe Mode, recovery, backgrounding, closure and blocked handoff; execution is pending repository CI. Windows sign-in, installed dashboard launch, real media/video, service account interoperability and Camera Hawk's existing certification gates remain unverified.
