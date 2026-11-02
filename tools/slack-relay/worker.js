// Neura Slack relay: a Cloudflare Worker behind the Slack slash command
//   /neura [launch | update | status]
// It checks that the request really came from Slack (signing secret), that the
// Slack user is on the allow-list, then asks GitHub to run the
// "Neura Remote Launch" workflow on the self-hosted Windows PC.
//
// Secrets (wrangler secret put ... or the Cloudflare dashboard):
//   SLACK_SIGNING_SECRET  Slack app > Basic Information > Signing Secret
//   GITHUB_TOKEN          fine-grained PAT: this repo only, "Actions: Read and write"
//   ALLOWED_SLACK_USERS   comma-separated Slack member IDs, e.g. U0123ABCD
// Plain variables (wrangler.toml [vars]):
//   GITHUB_REPO           owner/repo
//   GITHUB_REF            branch that holds the workflow (default branch)
//   WORKFLOW_FILE         neura-remote-launch.yml
//
// Setup: docs/REMOTE_LAUNCH.md

const MODES = new Set(['launch', 'update', 'status']);
const MAX_SKEW_SECONDS = 60 * 5;

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('Neura Slack relay is running.', { status: 200 });
    }

    const body = await request.text();
    if (!(await isFromSlack(request, body, env.SLACK_SIGNING_SECRET))) {
      return new Response('Invalid Slack signature.', { status: 401 });
    }

    const form = new URLSearchParams(body);
    const userId = form.get('user_id') || '';
    const userName = form.get('user_name') || userId;

    const allowed = (env.ALLOWED_SLACK_USERS || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    if (!allowed.includes(userId)) {
      return reply(`Sorry, you're not allowed to control Neura. (Your Slack ID is ${userId}.)`);
    }

    const word = (form.get('text') || '').trim().toLowerCase() || 'launch';
    if (word === 'help' || !MODES.has(word)) {
      return reply(
        '*Neura remote control*\n' +
          '`/neura` or `/neura launch` - open Neura on the PC\n' +
          '`/neura update` - pull the latest code, rebuild if needed, then open\n' +
          '`/neura status` - check whether Neura is running',
      );
    }

    const repo = env.GITHUB_REPO;
    const workflow = env.WORKFLOW_FILE || 'neura-remote-launch.yml';
    const res = await fetch(
      `https://api.github.com/repos/${repo}/actions/workflows/${workflow}/dispatches`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.GITHUB_TOKEN}`,
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'neura-slack-relay',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          ref: env.GITHUB_REF || 'Neura',
          inputs: { mode: word, requested_by: `Slack @${userName}`.slice(0, 100) },
        }),
      },
    );

    const runs = `https://github.com/${repo}/actions/workflows/${workflow}`;
    if (res.status === 204) {
      const what = {
        launch: 'Opening Neura on the PC',
        update: 'Updating, then opening Neura on the PC',
        status: 'Checking whether Neura is running',
      }[word];
      return reply(`${what}... the result shows up here: <${runs}|Neura Remote Launch runs>`);
    }

    const detail = (await res.text()).slice(0, 300);
    return reply(`GitHub refused the request (HTTP ${res.status}). ${detail}`);
  },
};

function reply(text) {
  return new Response(JSON.stringify({ response_type: 'ephemeral', text }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

// https://api.slack.com/authentication/verifying-requests-from-slack
async function isFromSlack(request, body, secret) {
  const timestamp = request.headers.get('X-Slack-Request-Timestamp');
  const signature = request.headers.get('X-Slack-Signature');
  if (!secret || !timestamp || !signature) return false;

  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Date.now() / 1000 - ts) > MAX_SKEW_SECONDS) {
    return false;
  }

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`v0:${timestamp}:${body}`));
  const expected = 'v0=' + [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return timingSafeEqual(expected, signature);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
