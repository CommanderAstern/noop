"""Require the connected Codex review of the current PR commit, as in Inkbook.

Uses GitHub metadata only. Never checks out or executes pull-request code.
Run with --publish to update the required status; API errors fail closed.
"""
import argparse
import json
import re
import subprocess

BOT = 'chatgpt-codex-connector'
MARKER = '<!-- codex-pull-request-review-summary -->'
CONTEXT = 'codex-review'

def api(path, *args):
    result = subprocess.run(['gh', 'api', path, *args], capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(result.stdout)

def pages(path):
    result = api(path + '?per_page=100', '--paginate', '--slurp')
    return [item for page in result for item in page]

def evaluate(pr, comments, threads, identity):
    if pr['state'] != 'open' or pr['draft'] or pr['base']['ref'] != 'personal':
        return 'PR must be ready for review and target personal.'
    head = pr['head']['sha']
    summaries = [c for c in comments if (c.get('performed_via_github_app') or {}).get('slug') == BOT
                 and c.get('user', {}).get('type') == 'Bot' and MARKER in (c.get('body') or '')]
    if not summaries:
        return 'Waiting for a connected Codex review.'
    body = max(summaries, key=lambda c: (c['updated_at'], c['id']))['body']
    rows = [line for line in body.splitlines() if '**Code Review**' in line]
    if len(rows) != 1 or '**Completed**' not in rows[0]:
        return 'Waiting for Codex to finish the review.'
    match = re.search(r'\|\s*`([0-9a-f]{7,64})`\s*\|', rows[0], re.I)
    short = identity.get('abbreviatedOid', '')
    if not match or identity.get('oid') != head or not re.fullmatch(r'[0-9a-f]{7,64}', short):
        return 'Unable to verify the reviewed commit identity.'
    reviewed = match[1].lower()
    if len(reviewed) < len(short) or not head.startswith(reviewed) or not head.startswith(short):
        return 'Waiting for Codex to review the current PR commit.'
    if any(not t['isResolved'] for t in threads):
        return 'Resolve all review threads before merging.'
    return None

def review_threads(repo, number):
    owner, name = repo.split('/')
    query = '''query($owner:String!,$name:String!,$number:Int!,$endCursor:String) {
      repository(owner:$owner,name:$name) { pullRequest(number:$number) {
        reviewThreads(first:100,after:$endCursor) { nodes { isResolved }
          pageInfo { hasNextPage endCursor } }
      } }
    }'''
    result = api('graphql', '-f', 'query=' + query, '-f', 'owner=' + owner, '-f', 'name=' + name,
                 '-F', 'number=' + str(number), '--paginate', '--slurp')
    threads = []
    for index, page in enumerate(result):
        if page.get('errors'):
            raise ValueError('GitHub review-thread query failed')
        connection = page['data']['repository']['pullRequest']['reviewThreads']
        if connection['pageInfo']['hasNextPage'] != (index < len(result) - 1):
            raise ValueError('Incomplete review-thread pagination')
        threads += connection['nodes']
    if not result or any(type(t.get('isResolved')) is not bool for t in threads):
        raise ValueError('Invalid review-thread metadata')
    return threads

def inspect(repo, number):
    pr = api(f'repos/{repo}/pulls/{number}')
    owner, name = repo.split('/')
    identity = api('graphql', '-f', '''query=query($owner:String!,$name:String!,$oid:GitObjectID!) {
      repository(owner:$owner,name:$name) { object(oid:$oid) { oid abbreviatedOid } }
    }''', '-f', 'owner=' + owner, '-f', 'name=' + name, '-f', 'oid=' + pr['head']['sha'])
    reason = evaluate(pr, pages(f'repos/{repo}/issues/{number}/comments'),
                      review_threads(repo, number), identity['data']['repository']['object'])
    return pr['head']['sha'], reason

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', default='CommanderAstern/noop')
    parser.add_argument('--pr', required=True, type=int)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    # Publish pending before evaluating; an API failure cannot preserve a previous success.
    head = api(f'repos/{args.repo}/pulls/{args.pr}')['head']['sha']
    def publish(state, description):
        if args.publish:
            api(f'repos/{args.repo}/statuses/{head}', '--method', 'POST', '-f', 'state=' + state,
                '-f', 'context=' + CONTEXT, '-f', 'description=' + description,
                '-f', f'target_url=https://github.com/{args.repo}/pull/{args.pr}')
    publish('pending', 'Checking the current Codex review and resolved findings.')
    current, reason = inspect(args.repo, args.pr)
    if not reason:
        # Re-read live review/head/thread state to reject races during API pagination.
        current2, reason = inspect(args.repo, args.pr)
        if current != head or current2 != head:
            reason = 'PR changed during review validation.'
    publish('pending' if reason else 'success', reason or 'Codex reviewed this commit; all findings are resolved.')
    print(reason or 'Codex review gate passed for ' + head)
    return 1 if reason else 0

if __name__ == '__main__':
    raise SystemExit(main())
