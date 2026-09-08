import copy
import unittest
from review_gate import evaluate, MARKER

class ReviewGateTests(unittest.TestCase):
    def setUp(self):
        self.head = 'abcdef0123456789abcdef0123456789abcdef01ff'
        self.pr = dict(state='open', draft=False, base=dict(ref='personal'), head=dict(sha=self.head))
        self.identity = dict(oid=self.head, abbreviatedOid=self.head[:7])
        self.summary = dict(id=1, updated_at='2026-09-08T12:00:00Z', user=dict(type='Bot'),
            performed_via_github_app=dict(slug='chatgpt-codex-connector'),
            body=MARKER + '\n| **Code Review** | **Completed** | `' + self.head[:7] + '` | PR opened |')

    def check(self, comments=None, threads=None):
        return evaluate(self.pr, comments if comments is not None else [self.summary],
                        threads if threads is not None else [], self.identity)

    def test_current_verified_review_passes(self):
        self.assertIsNone(self.check())
    def test_missing_review_blocks(self):
        self.assertIsNotNone(self.check(comments=[]))
    def test_user_forged_summary_blocks(self):
        self.summary['performed_via_github_app'] = {}
        self.assertIsNotNone(self.check())
    def test_old_review_blocks_new_push(self):
        self.pr['head']['sha'] = '1234567' + self.head[7:]
        self.assertIsNotNone(self.check())
    def test_unresolved_finding_blocks(self):
        self.assertIsNotNone(self.check(threads=[dict(isResolved=False)]))
        self.assertIsNone(self.check(threads=[dict(isResolved=True)]))
    def test_new_running_review_invalidates_completion(self):
        newer = copy.deepcopy(self.summary)
        newer['id'] = 2
        newer['body'] = newer['body'].replace('Completed', 'Running')
        self.assertIsNotNone(self.check(comments=[self.summary, newer]))
    def test_ambiguous_short_hash_blocks(self):
        self.identity['abbreviatedOid'] = self.head[:8]
        self.assertIsNotNone(self.check())
    def test_draft_closed_and_wrong_base_block(self):
        for key, value in [('draft', True), ('state', 'closed'), ('base', dict(ref='main'))]:
            previous = self.pr[key]
            self.pr[key] = value
            self.assertIsNotNone(self.check())
            self.pr[key] = previous
