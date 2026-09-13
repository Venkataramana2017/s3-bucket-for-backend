module.exports = async ({ github, context, env = process.env }) => {
  const { GATE_PHASE: phase, OPERATION: operation, PR_SHA: sha,
    PR_NUMBER: number, TERRAFORM_RESULT: result } = env;
  if (!['start', 'finish'].includes(phase) || !['plan', 'apply', 'destroy'].includes(operation) ||
      !/^[0-9a-f]{40}$/.test(sha || '') || !/^[1-9][0-9]*$/.test(number || '')) {
    throw new Error('Invalid merge gate inputs.');
  }
  const { data: pr } = await github.rest.pulls.get({ ...context.repo, pull_number: Number(number) });
  const eligible = pr.state === 'open' && !pr.draft && pr.head.sha === sha &&
    pr.head.repo?.full_name === `${context.repo.owner}/${context.repo.repo}`;
  let state = 'pending';
  let description = 'Merge blocked: waiting for successful /apply or /destroy.';
  if (!eligible) {
    state = 'failure';
    description = 'PR changed or is ineligible. Run a new command on the current open PR.';
  } else if (phase === 'finish' && result !== 'success') {
    state = 'failure';
    description = 'Terraform did not complete successfully. Run a new command.';
  } else if (phase === 'finish' && ['apply', 'destroy'].includes(operation)) {
    state = 'success';
    description = `Terraform ${operation} succeeded for this PR commit. Ready to merge.`;
  }
  await github.rest.repos.createCommitStatus({
    ...context.repo, sha, state, description,
    context: 'terraform-execution',
    target_url: `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`
  });
  if (!eligible) throw new Error(description);
};
