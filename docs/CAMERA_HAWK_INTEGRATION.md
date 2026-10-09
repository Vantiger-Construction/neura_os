# Camera Hawk integration in Neura OS

Neura's Windows viewer connects to a **separately installed and separately started Camera Hawk service on the same PC**. It lists registered camera names, locations and enabled flags. Live viewing happens in Camera Hawk's independent browser dashboard.

This guide covers the cumulative Camera Hawk v3.7 source/setup package used by PR #115. The commands below have been checked against that package's launcher source. They have **not been executed on a real Windows installation** as part of this documentation update. Neura does not include a Camera Hawk executable, install its backend, or start it automatically.

## 1. Locate the existing Camera Hawk installation

Use the existing **Camera_Hawk_One_Click** application folder containing:

- RUN_CAMERA_HAWK.cmd
- installer/ONE_CLICK_START.ps1 and its Python helpers
- services/camera-api/main.py and services/camera-api/requirements.txt
- services/camera-api/dashboard/ and services/camera-api/neura_vision/

Keep the whole application folder in place. A copied launcher or a Neura installer alone is insufficient. Do not guess a CameraHawk.exe path or Windows service name: neither is established by this source package.

If that folder is missing, obtain the existing **Camera_Hawk_v3_7_Drone_Watch_Bundle.zip**, use **Extract All** into a new writable folder, and open its Camera_Hawk_One_Click subfolder. Do not run from ZIP preview or overwrite an older application directory. The archive was available for this review; it is not included in Neura or published as a Neura download.

The archive's SHA-256, checked against the supplied Camera_Hawk_v3_7_SHA256.txt, is:

~~~text
3801c9fdcb4f9d67d724464dc4f12cf40103e6c095a7067b71495cb044a3ba44
~~~

Before upgrading, stop the old Camera Hawk console and managed media relay with **Ctrl+C**, then preserve an offline backup of the data and recordings. Keep the old source folder. If v3.7 has written drone events, do not reopen that live database with v3.6 or older; rollback needs a compatible offline backup.

### Prerequisites and existing data

- Use the **same Windows account that owns the existing Camera Hawk data and encrypted camera credentials**. Windows DPAPI camera credentials depend on that account. Moving to another Windows service account or PC needs separate validation.
- The launcher requires installed regular **x64 CPython 3.11-3.14**, including venv support. Python is not embedded. The source rejects 32-bit, prerelease and free-threaded builds.
- The application and selected data directories must be writable. Missing Python dependencies require access to the package index or usable cached wheels. The launcher installs/checks its own pinned environment; do not repair it by installing Uvicorn into an unrelated global Python.
- First-run account setup creates an **admin** account only when there are no existing users. Choose a new 12-256-character Camera Hawk password when prompted. There is no default password, and this is not your Windows or camera-device password. An existing enabled administrator and its password are preserved. Existing users with no enabled administrator require account recovery; the launcher does not reset or promote them.
- FFmpeg/FFprobe, MediaMTX and AI model weights are not bundled. They are unnecessary for Neura's metadata list. Camera probing/snapshots/recording need FFmpeg/FFprobe; browser live video needs a compatible MediaMTX executable plus a configured, reachable camera. AI model setup is separate.

The launcher's default data root is **%LOCALAPPDATA%\CameraHawkData**. Accounts/sessions are in auth.db under that root; the camera index defaults to camera_hawk.db, with recordings and snapshots subfolders. The launcher reuses saved data settings in the application folder. A new source folder does not silently import an old folder's custom settings.

If the existing installation uses custom locations, carry forward its actual absolute paths for **CAMERA_HAWK_DATA**, **CAMERA_HAWK_DB**, **CAMERA_HAWK_RECORDINGS** and **CAMERA_HAWK_SNAPSHOTS** before launching. Set them in the same PowerShell session used for the command below. Reuse those settings in the relay terminal too. Verify the paths printed by the launcher: a different data root can present different accounts/cameras. Do not select a new empty folder merely to solve a sign-in failure.

## 2. Start the independent service

Open PowerShell **in the existing Camera_Hawk_One_Click folder** and run:

~~~powershell
.\RUN_CAMERA_HAWK.cmd -Port 8799 -NoBrowser
~~~

The CMD wrapper forwards these options to installer/ONE_CLICK_START.ps1. It finds installed Python, verifies or prepares a private environment, completes administrator setup, and starts installer/serve_one_click.py. That server binds **127.0.0.1**, with port **8799**, one worker and no proxy-header trust. -NoBrowser suppresses only the launcher's automatic browser opening.

Wait for the console to print:

~~~text
CAMERA HAWK IS RUNNING: http://127.0.0.1:8799/
~~~

Keep this console open. In a browser on the same PC, visit **http://127.0.0.1:8799/health**. The v3.7 source returns ok=true, service=camera-hawk-api and version=3.7.0. This checks API availability, not sign-in, camera connectivity or video.

Double-clicking RUN_CAMERA_HAWK.cmd is also supported: it uses port 8799 and opens the dashboard after readiness. Use the same ordinary launcher on later starts. RUN_CAMERA_HAWK_DRONES.cmd and the one-file Camera_Hawk_v3_7_Drone_Setup.cmd additionally request drone-model preparation; they are not required to connect Neura.

If Python detection fails despite an installed supported interpreter, the wrapper accepts -PythonExe with its actual full python.exe path. -Console selects hidden terminal password input instead of the masked window. These are launcher options, not a reason to pass passwords in command arguments.

This is a **foreground console server**, not an installed Windows service. Follow the applicable Windows/organization script policy; these source launchers are unsigned. Their process-scoped execution-policy option does not establish that the package is approved or tested on your PC.

## 3. Prepare a Camera Hawk viewer account

Open **http://127.0.0.1:8799/** directly and sign in with the existing Camera Hawk administrator, or the admin account just created.

In **Accounts**, create an enabled account with role **viewer** and a password of 12-256 characters, or use an existing enabled viewer account. Use this account for Neura. If cameras are not registered yet, the administrator can add them under **Cameras** in Camera Hawk; camera-device credentials and stream addresses belong there.

Neura uses **username/password login**. A Windows account, camera-device account, Neura account or configured CAMERA_HAWK_API_KEY is not a substitute. The dashboard's optional service-key form is a separate administrator-equivalent authentication path; Neura does not send X-Camera-Hawk-Key or configure that secret.

Sign out of the administrator browser session after setup. Viewer permission is sufficient for reading the camera list and permitted browser live viewing.

## 4. Connect Neura

1. Open Neura on the same Windows PC, in the foreground, outside Safe Mode and recovery.
2. Open its command palette, search for **Camera Hawk**, and open the viewer.
3. Enter the Camera Hawk viewer username and password, then select **Sign in**.
4. Confirm the expected camera names, locations and Enabled/Disabled flags appear. **Refresh cameras** makes an explicit list request; Neura does not poll.

Neura calls POST /v1/auth/login, GET /v1/vision/cameras and, when ending authorization, POST /v1/auth/logout. It keeps the session credential in RAM, clears the password field after submission, and discards source URLs and vault references from the camera response. Nothing is copied into preferences, journal, chat, memory or logs.

An empty list means no registered cameras were returned by the selected installation; an Enabled flag is configuration metadata, not proof that a camera or live stream works. Android and web clients cannot use this connection to a Windows PC.

## 5. Open the dashboard and, optionally, live video

Select **Open camera dashboard** in Neura. It asks the Windows system browser to open **http://127.0.0.1:8799/**. If the browser does not open, enter that exact address manually on the same PC.

Sign in **separately** in the dashboard. Neura supplies no password, bearer token or service key in the URL and does not transfer its session to the browser. Bringing the browser forward may cause Neura to receive a background/inactive lifecycle event and clear its viewer authorization; returning to Neura does not restore it automatically.

Opening the dashboard does not prove live video works. For live viewing, keep the API console running and use Camera Hawk's separately installed MediaMTX relay:

1. Supply a trusted Windows mediamtx.exe compatible with the package's **MediaMTX v1.21 configuration format**. That binary is absent from the bundle; no particular installed binary has been certified here.
2. Open a second terminal in the **same application folder**, under the same Windows account and with the same data-directory settings.
3. Run the existing relay wrapper below, replacing the example executable path with the actual installed path:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\installer\START_MEDIAMTX.ps1 -MediaMtxExe 'C:\Tools\MediaMTX\mediamtx.exe'
~~~

The wrapper uses the selected Camera Hawk environment and runs services/camera-api/run_mediamtx.py. It generates configuration for enabled cameras whose privacy policy permits live viewing; source credentials are supplied to the media child process at runtime. Use the managed wrapper rather than the inert legacy config/mediamtx.yml. Generated media listeners remain loopback-only: HTTP 8888/8889 and WebRTC UDP 8189, with the authorization callback at API port 8799.

In the browser's **Cameras** panel, select **Live / stop** for the intended camera. Confirm the actual camera view, authorization and applicable privacy controls on Windows. Missing relay files, camera configuration, codecs or a failed WHEP handshake can prevent video even when Neura lists cameras. Camera images, snapshots and recordings remain outside Neura.

## 6. Safely end the sessions

1. While Camera Hawk is reachable, select **Disconnect** in Neura, or close the Camera Hawk viewer. Neura immediately discards its authorization and camera list and attempts server logout.
2. In each authenticated Camera Hawk browser tab, select **Sign out**, then close that tab. The dashboard's sign-out handler attempts to revoke its own bearer session, stops its live peers and clears its browser session state. Closing a tab alone is not documented server-token revocation.
3. If you intend to stop Camera Hawk itself, press **Ctrl+C** in its managed relay console, then in its API/launcher console. Stopping the backend interrupts its independent camera work; preserve data and recordings.

Backgrounding, Safe Mode and recovery also clear Neura authorization and metadata. A late login token is revoked and a late camera-list result is discarded. Logout is best effort when the API is unavailable; local clearing is immediate, while Camera Hawk still governs server token expiry. Returning to the foreground requires a new explicit sign-in.

**Neura Disconnect and Safe Mode do not sign out the browser, stop Camera Hawk, stop its recordings or stop camera firmware/another NVR.** End those independent sessions/processes separately. A configured service key is not revoked by signing out a bearer session.

## Troubleshooting and remaining setup gaps

| Symptom or gap | Next check |
| --- | --- |
| Launcher/folder is absent | Obtain the complete v3.7 bundle described above. Neura includes no backend installer or verified standalone EXE/Windows-service startup procedure. |
| Port 8799 is occupied | Identify the existing owner. If it is the intended healthy Camera Hawk API, use that instance; otherwise stop the old Camera Hawk console deliberately before retrying. The launcher does not kill arbitrary processes. Do not change ports to work around this: Neura's endpoint and the relay callback are fixed at 8799. |
| Startup/dependency/account setup fails | Check install-logs/latest-launch.log and install-logs/latest-admin.log. Verify supported Python, writable directories, package availability and an enabled administrator. Review logs for secrets before sharing; preserve account/data files. |
| Neura says it could not connect | Check the exact loopback health address, selected data paths, enabled username/password account and foreground/Safe Mode/recovery state. Requests refuse redirects, have 10-second response/stream timeouts and a 1 MiB JSON response cap. |
| Neura signed in but a list request failed | Disconnect, resolve the service/account issue, then sign in again. A failed refresh alone is not a guaranteed logout. |
| Cameras/accounts differ from the existing installation | Confirm the Windows account and printed data settings. A different auth.db/camera_hawk.db can explain the difference; the user's actual installation path and custom settings were not inspected remotely. |
| Dashboard opens but no video plays | Supply the missing relay binary; verify the actual camera and credentials, privacy permission, generated configuration, authenticated WHEP exchange and browser/codec support. An HTML page or enabled flag is not media certification. |
| Camera credential decryption fails after changing Windows account | Check the original DPAPI-owning account. Cross-account service deployment and vault migration have no validated procedure in this integration. |

The bundle contains source and setup scripts, not a signed native Windows installer. Regular Python, exact pinned package wheels, FFmpeg/FFprobe, the MediaMTX executable, real camera configuration and a usable Camera Hawk account must be supplied where needed. The package's existing validation report says the full exact-pinned clean environment and native Windows execution were not completed. This guide cannot claim those prerequisites are satisfied on the user's PC.

## Evidence and real Windows acceptance gates

Source inspection for this update verified the archive checksum/CRC and traced the commands and UI labels above. It did not execute the Windows launchers, install dependencies, start cameras or modify the Camera Hawk backend.

PR #115's final head was **0b7fd66248ddbba45b0dec041b1a1b6bb1feb4d5**; it merged on October 8, 2026 as **30572c481d2b1ca6c6db7c3e5abe7244e5257fb5**. All three final PR runs succeeded:

- [Windows Local Runner](https://github.com/Vantiger-Construction/neura_os/actions/runs/37730808508)
- [Android Package](https://github.com/Vantiger-Construction/neura_os/actions/runs/37730808505)
- [State Matrix](https://github.com/Vantiger-Construction/neura_os/actions/runs/37730808517)

The documented **12 focused Flutter tests** passed under Flutter 3.47.5 in an isolated Linux package using the committed source, a Windows platform override and mocked HTTP: seven client/session tests and five widget/lifecycle tests. These support the Neura boundary behavior, not real Windows service interoperability. The successful Android build does not enable Android camera transport. These results belong to the final PR head, not a separate validation of every merged/default-branch commit.

| Real Windows gate still required | Evidence to collect without sending camera media to Neura |
| --- | --- |
| Existing installation startup or clean setup | Actual application path/version, launcher result, selected interpreter/data paths, expected health response, foreground shutdown and restart. |
| Accounts and vault | Administrator preservation/new setup, real viewer login/list/logout and native DPAPI round trip under the intended Windows account. The package supplies installer/TEST_DPAPI.ps1; its temporary-store test does not certify migration to a different account. |
| Installed Neura dashboard handoff | Browser launch from the packaged Windows app, separate login, viewer permissions, and no credential-bearing URL. |
| Lifecycle and offline logout | Disconnect, viewer closure, app exit, minimize/deactivation/background, Safe Mode and recovery; confirm authorization/list clearing and explicit re-login after foreground return, including service-unavailable logout. |
| Live camera/media certification | Authorized physical camera, actual MediaMTX binary/version, credential interoperability, privacy gates, WHEP/codec playback and clean relay shutdown. Retain camera/media evidence only in Camera Hawk or an explicitly chosen external test record. |

Source references within the reviewed Camera_Hawk_One_Click package:

- README.md, INSTALL_FIRST.md, docs/APP_GUIDE_v3_2.md and docs/V3_7_VALIDATION.md.
- RUN_CAMERA_HAWK.cmd; installer/ONE_CLICK_START.ps1, one_click.py, serve_one_click.py, setup_support.py and finish_admin_setup.py.
- installer/START_MEDIAMTX.ps1; services/camera-api/run_mediamtx.py and neura_vision/core/mediamtx.py.
- services/camera-api/main.py; neura_vision/api/auth_routes.py, api/routes.py, core/auth.py, core/security.py, core/config.py and core/credentials.py.
- services/camera-api/dashboard/index.html and dashboard.js.

Neura references: [client](../lib/modules/camera_hawk/camera_hawk_client.dart), [screen](../lib/modules/camera_hawk/camera_hawk_screen.dart), [client tests](../test/modules/camera_hawk_client_test.dart) and [screen tests](../test/modules/camera_hawk_screen_test.dart).

## Boundaries retained

- No Neura startup connection, periodic polling, automatic Camera Hawk installation/startup, discovery, media fetching, recording changes, PTZ/drone control or cloud calls.
- Fixed numeric loopback access only, bounded requests, redirect refusal, RAM-only Neura credentials and lifecycle authorization clearing.
- Independent backend/media/recording lifecycle and separate browser authentication.
- No camera images or recordings in Neura chat, journal, memory or exports.
- Windows only. Android remote transport and device validation remain future work.
