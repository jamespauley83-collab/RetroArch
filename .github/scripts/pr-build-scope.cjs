'use strict';

// Fail open: uncertain diffs must keep the build.
module.exports = async function needsBuild({ github, context, core }, isIsolated) {
  if (context.eventName !== 'pull_request') return true;
  const expected = context.payload.pull_request;
  if (!expected || !expected.head || !expected.base) return true;
  const params = { ...context.repo, pull_number: expected.number };
  const sameRevision = pr => pr.head.sha === expected.head.sha &&
    pr.base.sha === expected.base.sha;
  try {
    const { data: before } = await github.rest.pulls.get(params);
    if (!sameRevision(before) || !Number.isInteger(before.changed_files) ||
        before.changed_files < 1 || before.changed_files >= 3000) return true;
    const files = await github.paginate(github.rest.pulls.listFiles,
      { ...params, per_page: 100 });
    const { data: after } = await github.rest.pulls.get(params);
    if (!sameRevision(after) || after.changed_files !== before.changed_files ||
        files.length !== before.changed_files) return true;
    return files.some(file => {
      if (typeof file.filename !== 'string' || !isIsolated(file.filename)) return true;
      if (file.status === 'renamed' &&
          (typeof file.previous_filename !== 'string' ||
           !isIsolated(file.previous_filename))) return true;
      return false;
    });
  } catch (error) {
    core.warning('Could not establish an isolated change; keeping the full build.');
    return true;
  }
};
