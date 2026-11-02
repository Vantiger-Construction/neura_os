# Open Neura from Slack

Type `/neura` in Slack and Neura opens on the Windows PC.

```
Slack /neura  ->  Cloudflare Worker (tools/slack-relay)  ->  GitHub "Neura Remote Launch" workflow
              ->  self-hosted runner on the PC  ->  scheduled task in your signed-in session  ->  tools/Start-Neura.ps1
```

| Command | Effect |
| --- | --- |
| `/neura` or `/neura launch` | Open Neura. Does nothing if it is already running. |
| `/neura update` | Fast-forward the PC's checkout (only when clean and tracking a branch), rebuild if sources changed, open Neura. |
| `/neura status` | Report whether Neura is running. |
| `/neura help` | List the commands. |

Each run's result shows in the run summary under **Actions → Neura Remote Launch**.
The PC also logs every request to `%LOCALAPPDATA%\Neura\remote-launch.log`.

Why the scheduled task: an Actions runner cannot show a window on your desktop. It may
run as a service in session 0, and it stops every process a job started when the job
ends. So the workflow starts a task that runs in your own session instead.

Requirements: the PC is on, you are signed in to Windows, and the `neura` self-hosted
runner is online.

## 1. On the PC (once)

From the checkout Neura should launch from (for example `C:\Users\user1\neura_os_build`),
after this change is on that checkout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Register-NeuraRemoteLaunch.ps1
Start-ScheduledTask -TaskName 'Neura Remote Launch'   # Neura should open
```

The script detects which account the runner service uses and lets only that account
start the two tasks. If it warns that Windows refused the custom permissions, re-run it
from an elevated PowerShell. To remove the tasks, run it with `-Unregister`.

You can now also run **Actions → Neura Remote Launch → Run workflow** on GitHub.

## 2. GitHub token

Create a fine-grained personal access token at <https://github.com/settings/personal-access-tokens/new>:

- **Resource owner:** Vantiger-Construction, with **Only select repositories** set to `neura_os`.
- **Permissions:** Repository permissions → **Actions: Read and write**. Nothing else.
- If the organization requires approval for fine-grained tokens, approve it under the
  organization's settings → Personal access tokens.

## 3. Cloudflare Worker (free plan)

```powershell
cd tools\slack-relay
npx wrangler login
npx wrangler deploy                          # prints https://neura-slack-relay.<you>.workers.dev
npx wrangler secret put GITHUB_TOKEN          # paste the token from step 2
npx wrangler secret put ALLOWED_SLACK_USERS   # your Slack member ID, e.g. U0123ABCD
```

Find your member ID in Slack under **Profile → ⋮ → Copy member ID**. Separate several IDs
with commas.

## 4. Slack app

1. Go to <https://api.slack.com/apps> → **Create New App** → **From scratch**, name it
   `Neura`, and pick your workspace.
2. Under **Slash Commands** → **Create New Command**, enter:
   - Command: `/neura`
   - Request URL: the `workers.dev` URL from step 3
   - Short description: `Open Neura on my PC`
   - Usage hint: `[launch | update | status]`
3. Under **Install App**, install it to the workspace.
4. Under **Basic Information**, copy the **Signing Secret**, then:

   ```powershell
   npx wrangler secret put SLACK_SIGNING_SECRET
   ```

Type `/neura status` in any channel. The reply is visible only to you.

## Security

- The Worker rejects requests that are not signed with your Slack signing secret, or
  whose signature is more than 5 minutes old, which blocks replays.
- Only the Slack users in `ALLOWED_SLACK_USERS` can trigger a run. Anyone else gets their
  member ID back and nothing runs.
- Only three fixed modes reach the PC. The workflow passes them through an environment
  variable rather than interpolating them into a script, and it has read-only repository
  permissions.
- The GitHub token can only run workflows on this one repository.
- The desktop tasks run without elevation, only while you are signed in, and the runner
  account can only start them, not change them.

## Tests

```bash
node --test tools/slack-relay/worker.test.mjs
```
