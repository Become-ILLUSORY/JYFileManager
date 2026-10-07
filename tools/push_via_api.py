#!/usr/bin/env python3
"""通过 GitHub Git Data API 推送本地 HEAD 提交。

用途：沙箱里 github.com:443 不可达（但 api.github.com 通）时，
用 REST API 手工构造 blob/tree/commit 并更新 ref，达到与 git push 相同的效果。

设计要点：
- 以**远端 main** 作为新提交的父提交（远端 SHA 可能与本地不同，因为
  API 推送的提交时间不同 → SHA 不同）。
- 用「本地 HEAD 相对本地父提交的差异文件」作为本次要上传的内容。
  这样即使远端与本地历史 SHA 不同，只要**文件内容**一致，结果就一致。
- 上传前先逐文件核对「远端树」与「本地父提交树」的内容差异，
  有差异时打印出来，便于定位（正常情况下应为空）。
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


def remote_blob_map(tree_sha):
    """远端树的 path -> blob sha"""
    d = api('GET', f'/git/trees/{tree_sha}?recursive=1')
    return {e['path']: e['sha'] for e in d['tree'] if e['type'] == 'blob'}


def local_blob_map(commit):
    """本地提交的 path -> blob sha"""
    out = git('ls-tree', '-r', commit)
    m = {}
    for line in out.split('\n'):
        if not line.strip():
            continue
        meta, path = line.split('\t')
        m[path] = meta.split()[2]
    return m


def main():
    head = git('rev-parse', 'HEAD')
    parent = git('rev-parse', 'HEAD~1')
    message = git('log', '-1', '--format=%B')
    print(f'本地 HEAD={head[:8]} parent={parent[:8]}')

    changed = [f for f in git('diff', '--name-only', f'{parent}..{head}').split('\n') if f]
    print(f'本次变更 {len(changed)} 个文件')

    ref = api('GET', f'/git/ref/heads/{BRANCH}')
    remote_sha = ref['object']['sha']
    remote_commit = api('GET', f'/git/commits/{remote_sha}')
    print(f'远端 main = {remote_sha[:8]}')

    # 核对内容一致性：远端树 vs 本地父提交树
    rmap = remote_blob_map(remote_commit['tree']['sha'])
    lmap = local_blob_map(parent)
    diffs = sorted(p for p in set(rmap) & set(lmap) if rmap[p] != lmap[p])
    only_r = sorted(set(rmap) - set(lmap))
    only_l = sorted(set(lmap) - set(rmap))
    if diffs or only_r or only_l:
        print('注意：远端与本地父提交存在内容差异（将以本地为准覆盖本次变更文件）')
        if diffs:
            print(f'  内容不同（{len(diffs)}）: {diffs[:10]}')
        if only_r:
            print(f'  仅远端有: {only_r[:10]}')
        if only_l:
            print(f'  仅本地有: {only_l[:10]}')
    else:
        print('远端与本地父提交内容一致 ✓')

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
        print(f'  上传 {path}')

    tree = api('POST', '/git/trees', {
        'base_tree': remote_commit['tree']['sha'],
        'tree': tree_entries,
    })

    commit = api('POST', '/git/commits', {
        'message': message,
        'tree': tree['sha'],
        'parents': [remote_sha],
        'author': {'name': 'Become-ILLUSORY', 'email': 'becomeillusory@gmail.com'},
        'committer': {'name': 'Become-ILLUSORY', 'email': 'becomeillusory@gmail.com'},
    })
    print(f'新提交 {commit["sha"][:8]}')

    api('PATCH', f'/git/refs/heads/{BRANCH}', {'sha': commit['sha'], 'force': False})
    print('已更新远端 main ✓')
    with open('/tmp/remote_sha.txt', 'w') as f:
        f.write(commit['sha'])


if __name__ == '__main__':
    main()
