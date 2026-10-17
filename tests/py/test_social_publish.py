"""X3: tools/social_publish.py with mock adapters and a fake provider HTTP layer. No network, no database.
Checks: dry run claims nothing, the switch and the server flag are both needed, each row is reported once, failures carry a short reason,
no secret is ever printed, adapter request shapes (Facebook text / photo / video, Instagram two steps, WhatsApp template only, webhook https only).
Run: python3 -I tests/py/test_social_publish.py   (from the repository root)"""
import contextlib
import io
import json
import os
import sys
import unittest
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import social_publish as sp  # noqa: E402
import ops_common as oc  # noqa: E402

SECRET = 'test_secret_token_abcdef123456'


class FakeApi:
    def __init__(self, claims=None):
        self.claims = list(claims or [])
        self.calls = []

    def rpc(self, fn, args=None):
        self.calls.append((fn, args or {}))
        if fn == 'social_publish_claim':
            return self.claims.pop(0) if self.claims else {'on': True, 'rows': []}
        return {'ok': True}

    def reports(self):
        return [a for f, a in self.calls if f == 'social_publish_report']


class MockAdapter:
    def __init__(self, fail=None):
        self.fail = fail
        self.sent = []

    def send(self, row):
        self.sent.append(row['id'])
        if self.fail:
            raise sp.AdapterError(self.fail)
        return 'test_post_%s' % row['id'], 'https://example.test/p/%s' % row['id']


def row(i, channel='facebook', **kw):
    d = {'id': i, 'channel': channel, 'item_id': 'test_item', 'title': 'test_title', 'caption_bn': 'test_বাংলা', 'caption_en': 'test caption',
         'hashtags': ['test_tag'], 'media': [], 'template_code': None, 'attempt': 1}
    d.update(kw)
    return d


class FakeResp:
    def __init__(self, body, code=200):
        self.body, self.code = body, code

    def read(self):
        return self.body if isinstance(self.body, bytes) else json.dumps(self.body).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Recorder:
    """Stands in for urllib.request.urlopen: records every request, returns canned replies in order."""

    def __init__(self, replies=None, error=None):
        self.replies = list(replies or [])
        self.error = error
        self.reqs = []

    def __call__(self, req, timeout=None):
        self.reqs.append({'url': req.full_url, 'method': req.get_method(), 'body': json.loads(req.data) if req.data else None,
                          'headers': dict(req.header_items())})
        if self.error:
            raise self.error
        return FakeResp(self.replies.pop(0) if self.replies else {})


class SocialPublishTests(unittest.TestCase):
    def setUp(self):
        self._orig = urllib.request.urlopen
        self._env = dict(os.environ)
        oc.REDACT.add(SECRET)

    def tearDown(self):
        urllib.request.urlopen = self._orig
        os.environ.clear()
        os.environ.update(self._env)

    # ---- switches and dry run ----
    def test_dry_run_is_the_default_and_claims_nothing(self):
        api = FakeApi()
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            r = sp.run(api, {}, limit=5, enabled=False)
        self.assertEqual(r['claimed'], 0)
        self.assertEqual(api.calls, [])
        self.assertIn('dry run', buf.getvalue())

    def test_both_the_flag_and_the_env_switch_are_needed(self):
        os.environ.pop('SOCIAL_SEND_ENABLED', None)
        api = FakeApi([{'on': True, 'rows': [row(1)]}])
        ad = MockAdapter()
        with contextlib.redirect_stderr(io.StringIO()):
            sp.main(['--send'], api=api, adapters={'facebook': ad})          # env missing -> dry
        self.assertEqual(api.calls, [])
        os.environ['SOCIAL_SEND_ENABLED'] = '1'
        with contextlib.redirect_stderr(io.StringIO()):
            sp.main([], api=api, adapters={'facebook': ad})                  # no --send -> dry
        self.assertEqual(api.calls, [])
        with contextlib.redirect_stderr(io.StringIO()):
            sp.main(['--send', '--dry-run'], api=api, adapters={'facebook': ad})   # --dry-run always wins
        self.assertEqual(api.calls, [])

    def test_the_server_can_say_off_and_nothing_is_sent(self):
        api = FakeApi([{'on': False, 'reason': 'stopped', 'rows': []}])
        ad = MockAdapter()
        with contextlib.redirect_stderr(io.StringIO()):
            r = sp.run(api, {'facebook': ad}, enabled=True)
        self.assertFalse(r['server_on'])
        self.assertEqual(r['reason'], 'stopped')
        self.assertEqual(ad.sent, [])

    # ---- claim, report, failure reasons ----
    def test_each_claimed_row_is_posted_once_and_reported_with_its_reference(self):
        api = FakeApi([{'on': True, 'rows': [row(1), row(2)]}])
        ad = MockAdapter()
        r = sp.run(api, {'facebook': ad}, enabled=True)
        self.assertEqual(ad.sent, [1, 2])
        self.assertEqual((r['claimed'], r['published'], r['failed']), (2, 2, 0))
        reps = api.reports()
        self.assertEqual([x['p_id'] for x in reps], [1, 2])
        self.assertTrue(all(x['p_ok'] for x in reps))
        self.assertEqual(reps[0]['p_provider_post_id'], 'test_post_1')
        self.assertEqual(reps[0]['p_permalink'], 'https://example.test/p/1')
        self.assertIsNone(reps[0]['p_error'])

    def test_a_failure_is_reported_with_a_short_reason_and_the_run_goes_on(self):
        api = FakeApi([{'on': True, 'rows': [row(1), row(2)]}])
        bad = MockAdapter(fail='provider HTTP 500')
        good = MockAdapter()
        adapters = {'facebook': bad, 'instagram': good}
        api.claims[0]['rows'][1]['channel'] = 'instagram'
        r = sp.run(api, adapters, enabled=True)
        self.assertEqual((r['published'], r['failed']), (1, 1))
        reps = api.reports()
        self.assertFalse(reps[0]['p_ok'])
        self.assertEqual(reps[0]['p_error'], 'provider HTTP 500')
        self.assertIsNone(reps[0]['p_provider_post_id'])
        self.assertTrue(reps[1]['p_ok'])

    def test_a_row_for_an_unknown_channel_fails_that_row_only(self):
        api = FakeApi([{'on': True, 'rows': [row(7, channel='fax')]}])
        r = sp.run(api, {'facebook': MockAdapter()}, enabled=True)
        self.assertEqual(r['failed'], 1)
        self.assertEqual(api.reports()[0]['p_error'], 'unknown_channel')

    def test_an_unexpected_exception_is_reported_by_type_only(self):
        class Boom:
            def send(self, row):
                raise RuntimeError('secret ' + SECRET)
        api = FakeApi([{'on': True, 'rows': [row(3)]}])
        sp.run(api, {'facebook': Boom()}, enabled=True)
        self.assertEqual(api.reports()[0]['p_error'], 'adapter error: RuntimeError')
        self.assertNotIn(SECRET, json.dumps(api.calls))

    # ---- secrets ----
    def test_a_token_in_a_provider_error_is_never_printed(self):
        urllib.request.urlopen = Recorder(error=urllib.error.HTTPError('https://x', 401, 'bad', {}, None))
        ad = sp.FacebookPageAdapter('test_page', SECRET)
        buf = io.StringIO()
        api = FakeApi([{'on': True, 'rows': [row(4)]}])
        with contextlib.redirect_stderr(buf), contextlib.redirect_stdout(buf):
            sp.run(api, {'facebook': ad}, enabled=True)
            oc.log('printed', api.reports()[0].get('p_error'))
        self.assertNotIn(SECRET, buf.getvalue())
        self.assertNotIn(SECRET, json.dumps(api.calls))
        self.assertEqual(api.reports()[0]['p_error'], 'provider HTTP 401')

    def test_missing_secrets_fail_the_channel_with_a_name_not_a_value(self):
        with self.assertRaises(sp.AdapterError) as ctx:
            sp.build_adapters(lambda n, d='': '')['facebook'].send(row(1))
        self.assertIn('SOCIAL_FB_PAGE_ID', str(ctx.exception))
        self.assertNotIn(SECRET, str(ctx.exception))

    # ---- adapter request shapes (fake provider) ----
    def test_facebook_text_photo_and_video_shapes(self):
        rec = Recorder([{'id': 'p1'}, {'id': 'p2'}, {'id': 'p3'}])
        urllib.request.urlopen = rec
        os.environ['SOCIAL_MEDIA_BASE_URL'] = 'https://media.example.test/out'
        ad = sp.FacebookPageAdapter('test_page', SECRET)
        self.assertEqual(ad.send(row(1))[0], 'p1')
        self.assertTrue(rec.reqs[0]['url'].startswith('https://graph.facebook.com/v19.0/test_page/feed?'))
        self.assertIn('test caption', rec.reqs[0]['body']['message'])
        self.assertIn('#test_tag', rec.reqs[0]['body']['message'])
        ad.send(row(2, media=[{'path': 'test_p/1.jpg', 'kind': 'image', 'mime': 'image/jpeg', 'bytes': 10}]))
        self.assertTrue(rec.reqs[1]['url'].endswith('/test_page/photos?access_token=' + SECRET))
        self.assertEqual(rec.reqs[1]['body']['url'], 'https://media.example.test/out/test_p/1.jpg')
        ad.send(row(3, media=[{'path': 'test_p/v.mp4', 'kind': 'video', 'mime': 'video/mp4', 'bytes': 10}]))
        self.assertIn('/videos?', rec.reqs[2]['url'])
        self.assertIn('file_url', rec.reqs[2]['body'])

    def test_media_without_a_public_base_url_is_a_failure_not_a_guess(self):
        os.environ.pop('SOCIAL_MEDIA_BASE_URL', None)
        rec = Recorder([{'id': 'x'}])
        urllib.request.urlopen = rec
        ad = sp.FacebookPageAdapter('test_page', SECRET)
        with self.assertRaises(sp.AdapterError) as ctx:
            ad.send(row(5, media=[{'path': 'test_p/1.jpg', 'kind': 'image', 'mime': 'image/jpeg', 'bytes': 10}]))
        self.assertIn('media_url_not_configured', str(ctx.exception))
        self.assertEqual(rec.reqs, [])

    def test_instagram_is_two_steps_and_needs_media(self):
        rec = Recorder([{'id': 'creation_1'}, {'id': 'media_9'}])
        urllib.request.urlopen = rec
        os.environ['SOCIAL_MEDIA_BASE_URL'] = 'https://media.example.test/out'
        ad = sp.InstagramAdapter('test_ig', SECRET)
        with self.assertRaises(sp.AdapterError):
            ad.send(row(6))
        self.assertEqual(rec.reqs, [])
        ref, _ = ad.send(row(6, media=[{'path': 'test_p/1.jpg', 'kind': 'image', 'mime': 'image/jpeg', 'bytes': 10}]))
        self.assertEqual(ref, 'media_9')
        self.assertTrue(rec.reqs[0]['url'].startswith('https://graph.facebook.com/v19.0/test_ig/media?'))
        self.assertEqual(rec.reqs[0]['body']['image_url'], 'https://media.example.test/out/test_p/1.jpg')
        self.assertTrue(rec.reqs[1]['url'].startswith('https://graph.facebook.com/v19.0/test_ig/media_publish?'))
        self.assertEqual(rec.reqs[1]['body'], {'creation_id': 'creation_1'})

    def test_whatsapp_is_a_template_message_with_the_language_from_settings(self):
        rec = Recorder([{'messages': [{'id': 'wamid.test1'}]}])
        urllib.request.urlopen = rec
        ad = sp.WhatsAppTemplateAdapter('test_phone_id', SECRET, 'test_lang')
        ref, _ = ad.send(row(8, channel='whatsapp', to='+8801711099001', template_code='test_tpl'))
        self.assertEqual(ref, 'wamid.test1')
        body = rec.reqs[0]['body']
        self.assertEqual(body['type'], 'template')
        self.assertEqual(body['to'], '8801711099001')
        self.assertEqual(body['template'], {'name': 'test_tpl', 'language': {'code': 'test_lang'}})
        self.assertEqual(rec.reqs[0]['headers'].get('Authorization'), 'Bearer ' + SECRET)
        with self.assertRaises(sp.AdapterError):
            sp.WhatsAppTemplateAdapter('test_phone_id', SECRET, '').send(row(9, channel='whatsapp', to='+8801711099001', template_code='test_tpl'))
        with self.assertRaises(sp.AdapterError) as ctx:
            ad.send(row(10, channel='whatsapp', to='+8801711099001', template_code=None))
        self.assertEqual(str(ctx.exception), 'template_required')

    def test_webhook_must_be_https_and_gets_the_row_as_json(self):
        with self.assertRaises(sp.AdapterError):
            sp.GenericWebhookAdapter('http://insecure.example.test/hook', SECRET)
        rec = Recorder([{'id': 'wh_1'}])
        urllib.request.urlopen = rec
        ref, _ = sp.GenericWebhookAdapter('https://hooks.example.test/x', SECRET).send(row(11, channel='webhook'))
        self.assertEqual(ref, 'wh_1')
        self.assertEqual(rec.reqs[0]['body']['caption'], caption_check())

    def test_a_webhook_on_a_plain_http_address_sends_nothing(self):
        rec = Recorder([{'id': 'x'}])
        urllib.request.urlopen = rec
        env = lambda n, d='': 'http://insecure.example.test/hook' if n == 'SOCIAL_WEBHOOK_URL' else d
        with self.assertRaises(sp.AdapterError) as ctx:
            sp.build_adapters(env)['webhook'].send(row(12, channel='webhook'))
        self.assertIn('https', str(ctx.exception))
        self.assertEqual(rec.reqs, [])


def caption_check():
    return 'test_বাংলা\n\ntest caption\n\n#test_tag'


if __name__ == '__main__':
    res = unittest.main(exit=False, verbosity=1).result
    print('RESULT pass=%d fail=%d' % (res.testsRun - len(res.failures) - len(res.errors), len(res.failures) + len(res.errors)))
    sys.exit(0 if res.wasSuccessful() else 1)
