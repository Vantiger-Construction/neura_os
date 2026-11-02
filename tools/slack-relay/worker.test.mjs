// node --test tools/slack-relay/worker.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import worker from './worker.js';

const env = {
  SLACK_SIGNING_SECRET: 'test-secret',
  GITHUB_TOKEN: 'ghp_test',
  ALLOWED_SLACK_USERS: 'U_ALLOWED, U_OTHER',
  GITHUB_REPO: 'owner/repo',
  GITHUB_REF: 'Neura',
  WORKFLOW_FILE: 'neura-remote-launch.yml',
};

function slackRequest(fields, { secret = env.SLACK_SIGNING_SECRET, skew = 0 } = {}) {
  const body = new URLSearchParams(fields).toString();
  const ts = String(Math.floor(Date.now() / 1000) - skew);
  const sig = 'v0=' + createHmac('sha256', secret).update(`v0:${ts}:${body}`).digest('hex');
  return new Request('https://relay.example/', {
    method: 'POST',
    headers: {
      'X-Slack-Request-Timestamp': ts,
      'X-Slack-Signature': sig,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
}

function stubGitHub(status = 204) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return new Response(status === 204 ? null : 'nope', { status });
  };
  return calls;
}

async function text(res) {
  return JSON.parse(await res.text()).text;
}

test('rejects a bad signature without calling GitHub', async () => {
  const calls = stubGitHub();
  const res = await worker.fetch(slackRequest({ user_id: 'U_ALLOWED' }, { secret: 'wrong' }), env);
  assert.equal(res.status, 401);
  assert.equal(calls.length, 0);
});

test('rejects a stale timestamp (replay)', async () => {
  const calls = stubGitHub();
  const res = await worker.fetch(slackRequest({ user_id: 'U_ALLOWED' }, { skew: 600 }), env);
  assert.equal(res.status, 401);
  assert.equal(calls.length, 0);
});

test('refuses users not on the allow-list', async () => {
  const calls = stubGitHub();
  const res = await worker.fetch(slackRequest({ user_id: 'U_STRANGER', text: 'launch' }), env);
  assert.match(await text(res), /not allowed/);
  assert.equal(calls.length, 0);
});

test('bare /neura dispatches launch on the configured ref', async () => {
  const calls = stubGitHub();
  const res = await worker.fetch(slackRequest({ user_id: 'U_ALLOWED', user_name: 'steven', text: '' }), env);
  assert.match(await text(res), /Opening Neura/);
  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    'https://api.github.com/repos/owner/repo/actions/workflows/neura-remote-launch.yml/dispatches',
  );
  assert.equal(calls[0].init.headers.Authorization, 'Bearer ghp_test');
  assert.deepEqual(calls[0].body, { ref: 'Neura', inputs: { mode: 'launch', requested_by: 'Slack @steven' } });
});

test('update and status map to their modes', async () => {
  for (const mode of ['update', 'STATUS ']) {
    const calls = stubGitHub();
    await worker.fetch(slackRequest({ user_id: 'U_OTHER', text: mode }), env);
    assert.equal(calls[0].body.inputs.mode, mode.trim().toLowerCase());
  }
});

test('unknown words show help and dispatch nothing', async () => {
  const calls = stubGitHub();
  const res = await worker.fetch(slackRequest({ user_id: 'U_ALLOWED', text: 'rm -rf' }), env);
  assert.match(await text(res), /Neura remote control/);
  assert.equal(calls.length, 0);
});

test('reports a GitHub refusal', async () => {
  stubGitHub(403);
  const res = await worker.fetch(slackRequest({ user_id: 'U_ALLOWED', text: 'launch' }), env);
  assert.match(await text(res), /HTTP 403/);
});
