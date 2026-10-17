'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const needsBuild = require('./pr-build-scope.cjs');
const isolated = p => p.startsWith('pkg/apple/ipad-lab/') ||
  ['.github/workflows/ipad-lab.yml', '.github/workflows/ipad-lab-armsx2.yml'].includes(p);
function fixture(files, options = {}) {
  const pr = { number: 11, head: { sha: 'head' }, base: { sha: 'base' },
    changed_files: files.length };
  let calls = 0;
  return { context: { eventName: options.event || 'pull_request',
      repo: { owner: 'owner', repo: 'repo' }, payload: { pull_request: pr } },
    core: { warning() {} },
    github: { rest: { pulls: { listFiles() {}, async get() {
      calls++;
      if (options.error) throw Error('API unavailable');
      return { data: { ...pr, ...options.metadata,
        ...(calls === 2 ? options.after : {}) } };
    } } }, async paginate(method, params) {
      assert.equal(params.per_page, 100);
      return options.returned || files;
    } } };
}
for (const event of ['push', 'release', 'workflow_dispatch', 'repository_dispatch']) {
  test(event + ' always builds', async () =>
    assert.equal(await needsBuild(fixture([], { event }), isolated), true));
}
test('isolated iPad files and workflow skip unrelated builds', async () =>
  assert.equal(await needsBuild(fixture([
    { filename: 'pkg/apple/ipad-lab/app.swift' },
    { filename: '.github/workflows/ipad-lab-armsx2.yml' }
  ]), isolated), false));
for (const filename of ['retroarch.c', 'libretro-common/memmap/memmap.c',
  'pkg/apple/BaseConfig.xcconfig', 'Makefile', '.github/workflows/Wii.yml',
  '.github/scripts/pr-build-scope.cjs']) {
  test(filename + ' keeps broad coverage', async () =>
    assert.equal(await needsBuild(fixture([
      { filename: 'pkg/apple/ipad-lab/app.swift' }, { filename }
    ]), isolated), true));
}
test('rename from shared code keeps coverage', async () =>
  assert.equal(await needsBuild(fixture([{ filename: 'pkg/apple/ipad-lab/file.c',
    previous_filename: 'retroarch.c', status: 'renamed' }]), isolated), true));
test('rename inside isolation skips', async () =>
  assert.equal(await needsBuild(fixture([{ filename: 'pkg/apple/ipad-lab/new.c',
    previous_filename: 'pkg/apple/ipad-lab/old.c', status: 'renamed' }]), isolated), false));
test('missing rename origin keeps coverage', async () =>
  assert.equal(await needsBuild(fixture([{ filename: 'pkg/apple/ipad-lab/new.c',
    status: 'renamed' }]), isolated), true));
test('empty, incomplete, oversized, failed and moving diffs keep coverage', async () => {
  const files = [{ filename: 'pkg/apple/ipad-lab/app.swift' }];
  for (const [input, options] of [[[], {}], [files, { metadata: { changed_files: 2 } }],
    [files, { metadata: { changed_files: 3000 } }], [files, { error: true }],
    [files, { metadata: { head: { sha: 'new' } } }],
    [files, { after: { base: { sha: 'new-base' } } }]]) {
    assert.equal(await needsBuild(fixture(input, options), isolated), true);
  }
});
test('paginate includes shared code beyond the first 300 files', async () => {
  const files = Array.from({ length: 350 }, (_, i) =>
    ({ filename: 'pkg/apple/ipad-lab/' + i }));
  files.push({ filename: 'retroarch.c' });
  assert.equal(await needsBuild(fixture(files), isolated), true);
});
test('docs-only scope is narrow', async () => {
  const docs = p => ['README.md', 'WINDOWS_START_HERE.md'].includes(p) ||
    /^docs\/.*\.md$/.test(p);
  assert.equal(await needsBuild(fixture([{ filename: 'docs/PLAN.md' }]), docs), false);
  for (const filename of ['iOS/App/RootView.swift', 'Package.swift',
    'docs/signing.mobileprovision', 'scripts/build_ios.sh', '.github/workflows/verify.yml']) {
    assert.equal(await needsBuild(fixture([{ filename }]), docs), true);
  }
});
