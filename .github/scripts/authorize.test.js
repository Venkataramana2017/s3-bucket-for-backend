const { test } = require('node:test');
const assert = require('node:assert/strict');
const authorize = require('./authorize');

function fixture({ command = '/plan', permission = 'write', state = 'open', draft = false,
  fork = false, event = 'issue_comment', stale = false, issueOnly = false } = {}) {
  const outputs = {};
  const sha = 'a'.repeat(40);
  return {
    outputs,
    input: {
      github: { rest: {
        repos: { getCollaboratorPermissionLevel: async () => ({ data: { permission } }) },
        pulls: { get: async () => ({ data: { state, draft, head: {
          sha, repo: { full_name: fork ? 'outsider/repo' : 'owner/repo' }
        } } }) }
      } },
      context: {
        repo: { owner: 'owner', repo: 'repo' }, actor: 'writer', eventName: event,
        payload: {
          issue: { number: 4, pull_request: issueOnly ? undefined : {} },
          comment: { body: command },
          pull_request: { number: 4, head: { sha: stale ? 'b'.repeat(40) : sha } }
        }
      },
      core: { setOutput: (key, value) => { outputs[key] = value; } }
    }
  };
}

for (const operation of ['plan', 'apply', 'destroy']) {
  test(`accepts exact /${operation} and captures PR head`, async () => {
    const { input, outputs } = fixture({ command: `/${operation}` });
    await authorize(input);
    assert.deepEqual(outputs, { operation, sha: 'a'.repeat(40), pr: 4 });
  });
}
for (const command of ['please /apply', '/destroy; echo bad', 'terraform apply', '/apply\nextra', 'hello', '/terraform apply']) {
  test(`ignores non-command: ${JSON.stringify(command)}`, async () => {
    const { input, outputs } = fixture({ command });
    await authorize(input);
    assert.deepEqual(outputs, {});
  });
}
for (const permission of ['read', 'triage', 'none']) {
  test(`rejects ${permission} permission`, async () => {
    await assert.rejects(authorize(fixture({ permission }).input), /write permission/);
  });
}
for (const [settings, message] of [
  [{ fork: true }, /Fork PRs are not supported/],
  [{ draft: true }, /is a draft/],
  [{ state: 'closed' }, /is closed.*open PR/]
]) {
  test(`rejects ineligible PR ${JSON.stringify(settings)}`, async () => {
    await assert.rejects(authorize(fixture(settings).input), message);
  });
}
test('ordinary issue comment is ignored', async () => {
  const { input, outputs } = fixture({ issueOnly: true });
  await authorize(input);
  assert.deepEqual(outputs, {});
});
test('PR event plans automatically', async () => {
  const { input, outputs } = fixture({ event: 'pull_request_target' });
  await authorize(input);
  assert.equal(outputs.operation, 'plan');
});
test('stale PR event is rejected', async () => {
  await assert.rejects(authorize(fixture({ event: 'pull_request_target', stale: true }).input), /stale/);
});
test('reruns cannot replay authorization', async () => {
  process.env.GITHUB_RUN_ATTEMPT = '2';
  try { await assert.rejects(authorize(fixture().input), /rerunning/); }
  finally { delete process.env.GITHUB_RUN_ATTEMPT; }
});
