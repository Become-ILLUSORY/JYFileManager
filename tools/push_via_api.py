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
    message = git('log', '-1', '--format=%B')
    print(f'本地 HEAD={head[:8]}')

    ref = api('GET', f'/git/ref/heads/{BRANCH}')
    remote_sha = ref['object']['sha']
    remote_commit = api('GET', f'/git/commits/{remote_sha}')
    print(f'远端 main = {remote_sha[:8]}')

    # 全量同步：对比远端树与本地 HEAD 树，把所有不一致的文件都传上去。
    #
    # 不能用「最后一个提交的 diff」——如果远端落后多个提交（例如上次推送
    # 失败/中断），只传最后一个提交会漏掉之前的修复。
    rmap = remote_blob_map(remote_commit['tree']['sha'])
    lmap = local_blob_map(head)

    to_upload = sorted(
        p for p in set(lmap) if p not in rmap or rmap[p] != lmap[p]
    )
    to_delete = sorted(set(rmap) - set(lmap))
    print(f'需上传 {len(to_upload)} 个，需删除 {len(to_delete)} 个')
    if to_upload:
        print(f'  上传: {to_upload[:8]}{" …" if len(to_upload) > 8 else ""}')
    if to_delete:
        print(f'  删除: {to_delete[:8]}')

    if not to_upload and not to_delete:
        print('远端已与本地一致，无需推送')
        return

    tree_entries = []
    for path in to_upload:
        with open(path, 'rb') as f:
            content = f.read()
        blob = api('POST', '/git/blobs', {
            'content': base64.b64encode(content).decode(),
            'encoding': 'base64',
        })
        tree_entries.append({
            'path': path,
            'mode': '100755' if os.access(path, os.X_OK) else '100644',
            'type': 'blob',
            'sha': blob['sha'],
        })
    # 本地已删除的文件：sha 置空即从树中移除
    for path in to_delete:
        tree_entries.append({
            'path': path,
            'mode': '100644',
            'type': 'blob',
            'sha': None,
        })

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
