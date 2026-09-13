const { test } = require('node:test');
const assert = require('node:assert/strict');
const gate = require('./merge-gate');

function fixture(overrides = {}, prOverrides = {}) {
  const sha = 'a'.repeat(40);
  const statuses = [];
  return {
    statuses,
    input: {
      env: { GATE_PHASE: 'finish', OPERATION: 'apply', PR_SHA: sha,
        PR_NUMBER: '4', TERRAFORM_RESULT: 'success', ...overrides },
      context: { repo: { owner: 'owner', repo: 'repo' }, serverUrl: 'https://github.com', runId: 123 },
      github: { rest: {
        pulls: { get: async () => ({ data: { state: 'open', draft: false,
          head: { sha, repo: { full_name: 'owner/repo' } }, ...prOverrides } }) },
        repos: { createCommitStatus: async status => statuses.push(status) }
      } }
    }
  };
}
for (const operation of ['plan', 'apply', 'destroy']) {
  test(`${operation} starts with merge blocked`, async () => {
    const f = fixture({ OPERATION: operation, GATE_PHASE: 'start' });
    await gate(f.input);
    assert.equal(f.statuses[0].state, 'pending');
  });
  test(`${operation} completion has the correct merge eligibility`, async () => {
    const f = fixture({ OPERATION: operation });
    await gate(f.input);
    assert.equal(f.statuses[0].state, operation === 'plan' ? 'pending' : 'success');
    assert.equal(f.statuses[0].sha, f.input.env.PR_SHA);
    assert.equal(f.statuses[0].context, 'terraform-execution');
  });
  for (const result of ['failure', 'cancelled', 'skipped', '']) {
    test(`${operation} ${result || 'missing result'} cannot unlock merge`, async () => {
      const f = fixture({ OPERATION: operation, TERRAFORM_RESULT: result });
      await gate(f.input);
      assert.equal(f.statuses[0].state, 'failure');
    });
  }
}
for (const pr of [
  { state: 'closed' }, { draft: true },
  { head: { sha: 'b'.repeat(40), repo: { full_name: 'owner/repo' } } },
  { head: { sha: 'a'.repeat(40), repo: { full_name: 'fork/repo' } } }
]) {
  test(`ineligible PR remains blocked: ${JSON.stringify(pr)}`, async () => {
    const f = fixture({}, pr);
    await assert.rejects(gate(f.input), /PR changed or is ineligible/);
    assert.equal(f.statuses[0].state, 'failure');
    assert.equal(f.statuses[0].sha, 'a'.repeat(40));
  });
}
test('invalid operation cannot post a success status', async () => {
  const f = fixture({ OPERATION: 'merge' });
  await assert.rejects(gate(f.input), /Invalid merge gate inputs/);
  assert.equal(f.statuses.length, 0);
});
