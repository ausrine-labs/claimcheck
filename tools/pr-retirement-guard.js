'use strict';

const RECEIPT_HEADER = 'PR RETIREMENT REVIEW v1';
const RECEIPT_MAX_AGE_MS = 15 * 60 * 1000;
const TRUSTED_AUTHOR_ASSOCIATIONS = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);

function hasValidReceipt(
  comments,
  { headSha, repositoryName, pullNumber, sourcePaths, authorizedActor, closedAt },
) {
  const exactHead = `- Exact head: \`${headSha}\``;
  const disposition = /- Disposition: `(superseded|abandoned|rejected)`/;
  const closedAtMs = Date.parse(closedAt);
  if (!authorizedActor || !Number.isFinite(closedAtMs)) return false;
  return comments.some((comment) => {
    const body = typeof comment.body === 'string' ? comment.body : '';
    const author = comment.user && comment.user.login;
    const createdAtMs = Date.parse(comment.created_at);
    const receiptAgeMs = closedAtMs - createdAtMs;
    if (
      typeof author !== 'string' ||
      author.toLowerCase() !== authorizedActor.toLowerCase() ||
      !TRUSTED_AUTHOR_ASSOCIATIONS.has(comment.author_association) ||
      !Number.isFinite(createdAtMs) ||
      receiptAgeMs < 0 ||
      receiptAgeMs > RECEIPT_MAX_AGE_MS ||
      !body.includes(RECEIPT_HEADER) ||
      !body.includes(`- Repository: \`${repositoryName}\``) ||
      !body.includes(`- PR: \`#${pullNumber}\``) ||
      !body.includes(exactHead) ||
      !body.includes('- Review summary: ') ||
      !body.includes('- Per-file review:') ||
      !body.includes('This receipt records content disposition before exact-head branch retirement.') ||
      !disposition.test(body)
    ) {
      return false;
    }
    const reviewedPaths = [];
    for (const line of body.split('\n')) {
      const match = line.match(/^  - `([^`]+)` → `(preserved_exact|preserved_rewritten|intentionally_dropped)` → `[^`]+`/);
      if (match) reviewedPaths.push(match[1]);
    }
    const expected = [...sourcePaths].sort();
    const recorded = [...new Set(reviewedPaths)].sort();
    return expected.length === recorded.length && expected.every((path, index) => path === recorded[index]);
  });
}

async function guardUnmergedClosure({ github, context, core }) {
  const pull = context.payload.pull_request;
  const repository = context.payload.repository;
  if (!pull || !repository) {
    throw new Error('pull_request and repository payloads are required');
  }
  if (pull.merged) {
    return { action: 'merged-noop' };
  }

  const owner = repository.owner.login;
  const repo = repository.name;
  const pullNumber = pull.number;
  const headSha = pull.head.sha;
  const headRef = pull.head.ref;
  const headRepo = pull.head.repo && pull.head.repo.full_name;
  const repositoryName = repository.full_name;
  const authorizedActor = context.actor || (context.payload.sender && context.payload.sender.login);
  const closedAt = pull.closed_at;
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner,
    repo,
    issue_number: pullNumber,
    per_page: 100,
  });
  const files = await github.paginate(github.rest.pulls.listFiles, {
    owner,
    repo,
    pull_number: pullNumber,
    per_page: 100,
  });
  const sourcePaths = files.map((file) => file.filename);

  if (hasValidReceipt(comments, {
    headSha,
    repositoryName,
    pullNumber,
    sourcePaths,
    authorizedActor,
    closedAt,
  })) {
    return { action: 'receipted-noop' };
  }

  const explanation = [
    'This unmerged PR was closed without a valid exact-head `PR RETIREMENT REVIEW v1` receipt.',
    '',
    'The governed lifecycle does not treat Close as completion. Review every changed file, then use the canonical `culturenet-brain/tools/retire-pr-branch.py` command with the full head SHA and Vilija’s exact approval.',
  ].join('\n');

  if (headRepo !== repositoryName) {
    await github.rest.issues.createComment({
      owner,
      repo,
      issue_number: pullNumber,
      body: `${explanation}\n\nThe head belongs to external repository \`${headRepo || 'unknown'}\`, so this guard could not safely restore or reopen it. Map Room review is required.`,
    });
    core.setFailed('Unreceipted fork-owned PR closure requires Map Room review.');
    return { action: 'fork-blocked' };
  }

  let ref;
  try {
    const response = await github.rest.git.getRef({ owner, repo, ref: `heads/${headRef}` });
    ref = response.data;
  } catch (error) {
    if (error.status !== 404) {
      throw error;
    }
  }

  if (!ref) {
    await github.rest.git.createRef({
      owner,
      repo,
      ref: `refs/heads/${headRef}`,
      sha: headSha,
    });
  } else if (ref.object.sha !== headSha) {
    await github.rest.issues.createComment({
      owner,
      repo,
      issue_number: pullNumber,
      body: `${explanation}\n\nThe branch now points to \`${ref.object.sha}\`, not the closed PR head \`${headSha}\`. The guard refused to overwrite it. Map Room review is required.`,
    });
    core.setFailed('Unreceipted PR closure found a changed branch head.');
    return { action: 'head-race-blocked' };
  }

  await github.rest.pulls.update({ owner, repo, pull_number: pullNumber, state: 'open' });
  await github.rest.issues.createComment({
    owner,
    repo,
    issue_number: pullNumber,
    body: `${explanation}\n\nThe exact branch head \`${headSha}\` was ${ref ? 'still present' : 'restored'} and this PR was reopened automatically.`,
  });
  core.setFailed('Unmerged PR closure was reversed because its retirement receipt was missing.');
  return { action: ref ? 'reopened' : 'restored-and-reopened' };
}

module.exports = { guardUnmergedClosure, hasValidReceipt };
