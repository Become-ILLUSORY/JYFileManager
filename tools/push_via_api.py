#!/usr/bin/env python3
"""通过 GitHub Git Data API 推送本地 HEAD 提交。

用途：沙箱里 github.com:443 不可达（但 api.github.com 通）时，
用 REST API 手工构造 blob/tree/commit 并更新 ref，达到与 git push 相同的效果。

注意：远端 SHA 可能与本地不同（例如上一次也是走 API 推送的，
提交时间不同 → SHA 不同）。因此这里以**远端 main** 作为父提交，
只把本地 HEAD 相对其本地父提交的差异文件传上去。
"""
import base64
import json
import os
import subprocess
import sys
import urllib.request

REPO = 'Become-ILLUSORY/JYFileManager'
BRANCH = 'main'
TOKEN = os.environ['GH_TOKEN']


def api(method, path, data=None):
    url = f'https://api.github.com/repos/{REPO}{path}'
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header('Authorization', f'token {TOKEN}')
    req.add_header('Accept', 'application/vnd.github+json')
    if body:
        req.add_header('Content-Type', 'application/json')
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def git(*args):
    return subprocess.check_output(['git', *args]).decode().strip()


def main():
    head = git('rev-parse', 'HEAD')
    parent = git('rev-parse', 'HEAD~1')
    message = git('log', '-1', '--format=%B')
    print(f'本地 HEAD={head[:8]} parent={parent[:8]}')

    changed = [f for f in git('diff', '--name-only', f'{parent}..{head}').split('\n') if f]
    print(f'变更文件 {len(changed)} 个')

    ref = api('GET', f'/git/ref/heads/{BRANCH}')
    remote_sha = ref['object']['sha']
    print(f'远端 main = {remote_sha[:8]}')

    # 校验远端与本地父提交内容一致（树相同即可，SHA 可能因时间不同而不同）
    remote_commit = api('GET', f'/git/commits/{remote_sha}')
    local_parent_tree = git('rev-parse', f'{parent}^{{tree}}')
    if remote_commit['tree']['sha'] != local_parent_tree:
        print('警告：远端树与本地父提交不一致，可能有他人提交，中止')
        print(f"  远端树 {remote_commit['tree']['sha'][:8]}")
        print(f"  本地树 {local_parent_tree[:8]}")
        sys.exit(1)
    print('远端树与本地父提交一致 ✓')

    base_tree = remote_commit['tree']['sha']
    tree_entries = []
    for path in changed:
        with open(path, 'rb') as f:
            content = f.read()
        blob = api('POST', '/git/blobs', {
            'content': base64.b64encode(content).decode(),
            'encoding': 'base64',
        })
        tree_entries.append({
            'path': path,
            'mode': '100644',
            'type': 'blob',
            'sha': blob['sha'],
        })
        print(f'  blob {path}')

    tree = api('POST', '/git/trees', {
        'base_tree': base_tree,
        'tree': tree_entries,
    })

    commit = api('POST', '/git/commits', {
        'message': message,
        'tree': tree['sha'],
        'parents': [remote_sha],
        'author': {
            'name': 'Become-ILLUSORY',
            'email': 'becomeillusory@gmail.com',
        },
        'committer': {
            'name': 'Become-ILLUSORY',
            'email': 'becomeillusory@gmail.com',
        },
    })
    print(f'新提交 {commit["sha"][:8]}')

    api('PATCH', f'/git/refs/heads/{BRANCH}', {'sha': commit['sha'], 'force': False})
    print('已更新远端 main ✓')
    with open('/tmp/remote_sha.txt', 'w') as f:
        f.write(commit['sha'])


if __name__ == '__main__':
    main()
