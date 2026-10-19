"""Build the pinned StikJIT framework and a Lab-only helper with the host toolchain."""
import hashlib
import plistlib
from pathlib import Path
import shutil
import subprocess

COMMIT = '32287268fa5824f9edce4cb359f5833ce0cf7b00'
REPOSITORY = 'https://github.com/StikDebug/StikJIT.git'


def run(*args, cwd=None):
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def build(source, work, artifacts, bundle_id):
    if not shutil.which('xcodegen'):
        raise RuntimeError('Install XcodeGen before building the JIT helper.')
    repo = work / 'StikJIT'
    run('git', 'init', repo)
    run('git', 'fetch', '--depth=1', REPOSITORY, COMMIT, cwd=repo)
    run('git', 'checkout', '--detach', 'FETCH_HEAD', cwd=repo)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    if actual != COMMIT:
        raise RuntimeError('Unexpected StikJIT revision.')
    run('xcodegen', 'generate', cwd=repo)
    products = work / 'jit-products'
    common = ['-configuration', 'Release', '-destination', 'generic/platform=iOS',
              'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=NO', 'CODE_SIGNING_ALLOWED=NO',
              'CODE_SIGNING_REQUIRED=NO', 'DEVELOPMENT_TEAM=',
              'CONFIGURATION_BUILD_DIR=' + str(products)]
    run('xcodebuild', '-project', repo / 'StikJIT.xcodeproj', '-scheme', 'StikJIT',
        '-derivedDataPath', work / 'StikDerived', *common, 'build')
    helper_source = work / 'jit-helper'
    shutil.copytree(source, helper_source)
    framework = products / 'StikJIT.framework'
    shutil.copytree(framework, helper_source / framework.name)
    run('xcodegen', 'generate', cwd=helper_source)
    run('xcodebuild', '-project', helper_source / 'RALabJITHelper.xcodeproj',
        '-scheme', 'RALabJITHelper', '-derivedDataPath', work / 'HelperDerived',
        *common, 'LAB_HOST_ID=' + bundle_id, 'build')
    run('tar', '--exclude=.git', '-czf', artifacts / 'StikJIT-source.tar.gz', '-C', repo, '.')
    shutil.copy2(repo / 'LICENSE', artifacts / 'StikJIT-LICENSE')
    record = {'repository': REPOSITORY, 'commit': COMMIT, 'helper_bundle_id': bundle_id + '.JITHelper',
              'framework_sha256': hashlib.sha256((framework / 'StikJIT').read_bytes()).hexdigest(),
              'helper_sha256': hashlib.sha256((products / 'RALabJITHelper.appex/RALabJITHelper').read_bytes()).hexdigest()}
    return products, record


def embed(app, products, source):
    for relative in ('Frameworks/StikJIT.framework', 'PlugIns/RALabJITHelper.appex'):
        target = app / relative
        target.parent.mkdir(exist_ok=True)
        shutil.copytree(products / target.name, target)
    host_info = plistlib.loads((app / 'Info.plist').read_bytes())
    helper_plist = app / 'PlugIns/RALabJITHelper.appex/Info.plist'
    helper_info = plistlib.loads(helper_plist.read_bytes())
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        helper_info[key] = host_info[key]
    helper_plist.write_bytes(plistlib.dumps(helper_info))
    shutil.copy2(source / 'LICENSE-idevice.txt', app / 'StikJIT-idevice-LICENSE.txt')
    shutil.copy2(source / 'NOTICE.md', app / 'StikJIT-NOTICE.md')
    shutil.copy2(source / 'LICENSE-MPL-2.0.txt', app / 'StikJIT-LICENSE.txt')
