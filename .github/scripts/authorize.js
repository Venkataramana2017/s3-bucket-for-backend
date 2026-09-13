module.exports = async ({ github, context, core }) => {
  if (Number(process.env.GITHUB_RUN_ATTEMPT || 1) !== 1) {
    throw new Error('Post a new command or push a new commit instead of rerunning an old authorization.');
  }
  const repo = context.repo;
  let operation = 'plan';
  let number;
  if (context.eventName === 'issue_comment') {
    if (!context.payload.issue.pull_request) return;
    const command = context.payload.comment.body.trim().match(
      /^\/(plan|apply|destroy)$/
    );
    if (!command) return;
    [, operation] = command;
    number = context.payload.issue.number;
  } else {
    number = context.payload.pull_request.number;
  }
  const { data: permission } = await github.rest.repos.getCollaboratorPermissionLevel({
    ...repo, username: context.actor
  });
  if (!['admin', 'maintain', 'write'].includes(permission.permission)) {
    throw new Error('Only repository collaborators with write permission can run Terraform.');
  }
  const { data: pr } = await github.rest.pulls.get({ ...repo, pull_number: number });
  if (pr.state !== 'open' || pr.draft || pr.head.repo?.full_name !== `${repo.owner}/${repo.repo}`) {
    throw new Error('Terraform requires an open, non-draft PR from this repository. Fork PRs are not supported.');
  }
  if (context.eventName === 'pull_request_target' && context.payload.pull_request.head.sha !== pr.head.sha) {
    throw new Error('This PR event is stale.');
  }
  core.setOutput('operation', operation);
  core.setOutput('sha', pr.head.sha);
  core.setOutput('pr', number);
};
