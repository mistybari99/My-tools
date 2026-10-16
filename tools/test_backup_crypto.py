#!/usr/bin/env python3
"""Tests for tools/backup_crypto.py and the encryption path of tools/backup_dump.py (item U-12). Needs nothing but Python 3 (the fake Supabase of tools/test_ops.py).

    python3 -m unittest tools/test_backup_crypto.py -v          (or: cd tools && python3 -m unittest test_backup_crypto -v)

Passphrases here are test strings, never real ones.
"""
import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import backup_crypto as bc  # noqa: E402
import backup_dump  # noqa: E402
import restore_backup  # noqa: E402
import test_ops as T  # noqa: E402

PW = 'test passphrase: purple-river-lamp-42'
PW2 = 'test passphrase: purple-river-lamp-43'
ENV = {'BACKUP_PASSPHRASE': PW}


def keys(pw=PW, salt=None):
    return bc.derive(pw, salt)


PINNED = 'f469992772a002eed8d6b04bf9e2c7d63e4bb02efd559488da375aeca4b65adc'


class CryptoUnit(unittest.TestCase):
    def test_round_trip_all_sizes(self):
        k = keys()
        for n in (0, 1, 15, 16, 17, 1000, bc.CHUNK - 1, bc.CHUNK, bc.CHUNK + 1, 2 * bc.CHUNK + 5):
            data = os.urandom(n)
            blob = bc.encrypt_bytes(k, 'sales.ndjson.gz', data)
            self.assertEqual(len(blob), len(bc.MAGIC) + bc.TAG_LEN + n)
            self.assertEqual(bc.decrypt_bytes(k, 'sales.ndjson.gz', blob), data, n)

    def test_deterministic_so_git_only_grows_by_real_changes(self):
        a, b = keys(), keys()
        data = b'row1\nrow2\n' * 50
        self.assertEqual(bc.encrypt_bytes(a, 'x', data), bc.encrypt_bytes(b, 'x', data))
        self.assertNotEqual(bc.encrypt_bytes(a, 'x', data), bc.encrypt_bytes(a, 'x', data + b'row3\n'))

    def test_plaintext_does_not_appear_in_the_file(self):
        data = b'customer NID 1234567890123 bank 000111222333'
        blob = bc.encrypt_bytes(keys(), 'customers.ndjson.gz', data)
        self.assertNotIn(b'NID', blob)
        self.assertNotIn(b'1234567890123', blob)
        self.assertNotIn(PW.encode(), blob)
        self.assertTrue(blob.startswith(b'BOSENC1\n'))

    def test_label_binds_the_file_to_its_table(self):
        k = keys()
        data = b'payload ' * 40
        blob = bc.encrypt_bytes(k, 'sales.ndjson.gz', data)
        self.assertNotEqual(blob, bc.encrypt_bytes(k, 'customers.ndjson.gz', data))
        with self.assertRaises(bc.CryptoError):
            bc.decrypt_bytes(k, 'customers.ndjson.gz', blob)

    def test_wrong_passphrase_fails_and_never_returns_garbage(self):
        blob = bc.encrypt_bytes(keys(PW), 'a', b'secret rows')
        with self.assertRaises(bc.CryptoError) as cm:
            bc.decrypt_bytes(keys(PW2), 'a', blob)
        self.assertNotIn(PW, str(cm.exception))
        self.assertNotIn(PW2, str(cm.exception))

    def test_every_kind_of_damage_is_detected(self):
        k = keys()
        blob = bytearray(bc.encrypt_bytes(k, 'a', b'x' * 300))
        for pos in (0, 7, 8, 15, 23, 24, 100, len(blob) - 1):       # magic, tag, body, last byte
            bad = bytearray(blob)
            bad[pos] ^= 0x01
            with self.assertRaises(bc.CryptoError, msg=f'byte {pos}'):
                bc.decrypt_bytes(k, 'a', bytes(bad))
        for cut in (0, 5, 23, 24, 100):                               # truncated
            with self.assertRaises(bc.CryptoError, msg=f'cut {cut}'):
                bc.decrypt_bytes(k, 'a', bytes(blob[:cut]) if cut != 100 else bytes(blob[:100]))
        with self.assertRaises(bc.CryptoError):
            bc.decrypt_bytes(k, 'a', bytes(blob) + b'x')              # appended
        with self.assertRaises(bc.CryptoError):
            bc.decrypt_bytes(k, 'a', b'plain text, not encrypted at all, long enough to pass the length test')

    def test_passphrase_rules(self):
        for bad in ('', 'short', 'x' * 15, None):
            with self.assertRaises(bc.CryptoError):
                bc.derive(bad)
        bc.derive('x' * 16)
        with self.assertRaises(bc.CryptoError):
            bc.keys_from_env({})
        with self.assertRaises(bc.CryptoError):
            bc.keys_from_env({'BACKUP_PASSPHRASE': ''})

    def test_salt_changes_the_key(self):
        data = b'abc' * 30
        a = bc.encrypt_bytes(keys(PW, None), 'a', data)
        b = bc.encrypt_bytes(keys(PW, '00ff00ff00ff00ff'), 'a', data)
        self.assertNotEqual(a, b)
        self.assertNotEqual(keys(PW, None).key_check(), keys(PW, '00ff00ff00ff00ff').key_check())
        self.assertEqual(bc.keys_from_env({'BACKUP_PASSPHRASE': PW, 'BACKUP_KDF_SALT': '00ff00ff00ff00ff'}).key_check(), keys(PW, '00ff00ff00ff00ff').key_check())

    def test_format_is_pinned(self):
        """A fixed key and text must always give the same bytes: if this fails the format changed and old backups would no longer open."""
        blob = bc.encrypt_bytes(keys('pinned test passphrase 0123456789'), 'sales.ndjson.gz', b'{"id":1}\n')
        self.assertEqual(hashlib.sha256(blob).hexdigest(), PINNED)

    def test_manifest_block_holds_no_secret(self):
        d = keys().describe()
        text = json.dumps(d)
        self.assertNotIn(PW, text)
        self.assertEqual(d['format'], 'BOSENC1')
        self.assertEqual(len(d['key_check']), 16)




class DumpEncrypted(unittest.TestCase):
    def run_dump(self, S, out, encrypt, env=ENV, setting=None):
        if setting is not None:
            S.F.hooks['_w1g_backup_settings'] = lambda b: setting
        with T.Quiet() as q:
            m = backup_dump.run(S.api(), out, page=4, encrypt=encrypt, env=env)
        return m, q.text

    def test_off_is_exactly_the_old_behaviour(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            m, _ = self.run_dump(S, out, 'off')
            self.assertNotIn('encryption', m)
            self.assertEqual(sorted(os.listdir(out)), ['customers.ndjson.gz', 'manifest.json', 'notes.ndjson.gz', 'sales.ndjson.gz'])
            self.assertFalse(any(v.get('encrypted') for v in m['tables'].values()))

    def test_auto_without_the_setting_is_plain(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:          # the fake has no _w1g_backup_settings: an older database
            m, _ = self.run_dump(S, out, 'auto', env={})
            self.assertNotIn('encryption', m)
            self.assertTrue(all(f.endswith('.ndjson.gz') or f == 'manifest.json' for f in os.listdir(out)))

    def test_auto_follows_the_rule_off(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            m, _ = self.run_dump(S, out, 'auto', env=ENV, setting={'encrypt_on': False, 'retention_days': None})
            self.assertNotIn('encryption', m)

    def test_auto_follows_the_rule_on(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            m, _ = self.run_dump(S, out, 'auto', setting={'encrypt_on': True, 'retention_days': None})
            self.assertEqual(m['encryption']['format'], 'BOSENC1')
            self.assertEqual(sorted(os.listdir(out)), ['customers.ndjson.gz.enc', 'manifest.json', 'notes.ndjson.gz.enc', 'sales.ndjson.gz.enc'], 'only encrypted files, no plain copy')
            self.assertTrue(S.F.log_rows[-1]['p_detail']['encrypted'])

    def test_on_without_a_passphrase_fails_and_leaves_no_plain_file(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            with T.Quiet(), self.assertRaises(RuntimeError) as cm:
                backup_dump.run(S.api(), out, page=4, encrypt='on', env={})
            self.assertIn('BACKUP_PASSPHRASE', str(cm.exception))
            self.assertEqual(os.listdir(out), [], 'nothing written, in particular no plain files')
            self.assertEqual(S.F.log_rows[-1]['p_status'], 'failed', 'the failure is logged so the app can warn')

    def test_on_with_a_short_passphrase_fails(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            with T.Quiet(), self.assertRaises(RuntimeError):
                backup_dump.run(S.api(), out, page=4, encrypt='on', env={'BACKUP_PASSPHRASE': 'short'})
            self.assertEqual(os.listdir(out), [])

    def test_main_exit_code_when_on_and_no_key(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            old = os.environ.pop('BACKUP_PASSPHRASE', None)
            try:
                with T.Quiet() as q:
                    rc = backup_dump.main(['--out', out, '--encrypt', 'on'], api=S.api())
            finally:
                if old is not None:
                    os.environ['BACKUP_PASSPHRASE'] = old
            self.assertEqual(rc, 1)
            self.assertNotIn(PW, q.text)

    def test_files_decrypt_back_to_the_plain_backup(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as plain, tempfile.TemporaryDirectory() as ref:
            m, _ = self.run_dump(S, enc, 'on')
            with T.Quiet():
                backup_dump.run(S.api(), ref, page=4, encrypt='off', log_run=False)
            for f in os.listdir(enc):
                if f.endswith('.enc'):
                    raw = T.slurp(os.path.join(enc, f))
                    self.assertTrue(raw.startswith(b'BOSENC1\n') and b'\x1f\x8b' not in raw[:12], 'the stored file is not a readable gzip')
            out = bc.decrypt_dir(enc, plain, bc.keys_from_env(ENV))
            self.assertNotIn('encryption', out)
            for t in ('customers', 'sales', 'notes'):
                self.assertEqual(T.slurp(os.path.join(plain, t + '.ndjson.gz')), T.slurp(os.path.join(ref, t + '.ndjson.gz')), t + ': the decrypted file is byte-identical to a plain backup')
                self.assertEqual(out['tables'][t]['file'], t + '.ndjson.gz')
            self.assertEqual(T.read_ndjson(os.path.join(plain, 'customers.ndjson.gz'))[0]['name'], 'C1')

    def test_restore_tools_work_on_the_decrypted_folder(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as plain, tempfile.TemporaryDirectory() as w:
            self.run_dump(S, enc, 'on')
            buf = io.StringIO()
            with contextlib.redirect_stderr(buf):
                self.assertEqual(bc.main(['decrypt', enc, plain], env=ENV), 0)
            target = os.path.join(w, 'restore.sql')
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(restore_backup.main([plain, '--out', target]), 0)
            self.assertIn('customers', T.slurp(target, 'r', encoding='utf-8'))

    def test_the_restore_tool_refuses_the_encrypted_folder(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as w:
            self.run_dump(S, enc, 'on')
            with T.Quiet():
                rc = restore_backup.main([enc, '--out', os.path.join(w, 'r.sql')])
            self.assertNotEqual(rc, 0, 'an encrypted folder must not be restorable without decrypting first')

    def test_wrong_passphrase_fails_at_the_door(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as plain:
            self.run_dump(S, enc, 'on')
            with self.assertRaises(bc.CryptoError) as cm:
                bc.decrypt_dir(enc, plain, keys(PW2))
            self.assertIn('wrong passphrase', str(cm.exception))
            self.assertEqual(os.listdir(plain), [], 'nothing was written')
            buf = io.StringIO()
            with contextlib.redirect_stderr(buf):
                self.assertEqual(bc.main(['decrypt', enc, plain], env={'BACKUP_PASSPHRASE': PW2}), 1)
            self.assertNotIn(PW2, buf.getvalue())

    def test_a_changed_or_swapped_file_is_caught(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as plain:
            self.run_dump(S, enc, 'on')
            p = os.path.join(enc, 'sales.ndjson.gz.enc')
            raw = bytearray(T.slurp(p))
            raw[-3] ^= 0x40
            with open(p, 'wb') as f:
                f.write(raw)
            with self.assertRaises(bc.CryptoError):
                bc.decrypt_dir(enc, plain, keys())
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as plain:
            self.run_dump(S, enc, 'on')
            a, b = os.path.join(enc, 'sales.ndjson.gz.enc'), os.path.join(enc, 'customers.ndjson.gz.enc')
            sa, sb = T.slurp(a), T.slurp(b)
            with open(a, 'wb') as f:
                f.write(sb)
            with open(b, 'wb') as f:
                f.write(sa)
            with self.assertRaises(bc.CryptoError):
                bc.decrypt_dir(enc, plain, keys())

    def test_same_data_same_bytes_night_after_night(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            self.run_dump(S, a, 'on')
            self.run_dump(S, b, 'on')
            for t in ('customers', 'sales', 'notes'):
                self.assertEqual(T.slurp(os.path.join(a, t + '.ndjson.gz.enc')), T.slurp(os.path.join(b, t + '.ndjson.gz.enc')))
            S.F.tables['sales'].append({'id': 'a99', 'total': 1})
            with tempfile.TemporaryDirectory() as c:
                self.run_dump(S, c, 'on')
                self.assertEqual(T.slurp(os.path.join(a, 'customers.ndjson.gz.enc')), T.slurp(os.path.join(c, 'customers.ndjson.gz.enc')), 'an unchanged table is identical')
                self.assertNotEqual(T.slurp(os.path.join(a, 'sales.ndjson.gz.enc')), T.slurp(os.path.join(c, 'sales.ndjson.gz.enc')), 'a changed table differs')

    def test_switching_the_mode_leaves_no_stale_copy(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            self.run_dump(S, out, 'off')
            self.run_dump(S, out, 'on')
            self.assertFalse(any(f.endswith('.ndjson.gz') for f in os.listdir(out)), 'a plain file from the earlier run must not stay next to the encrypted ones')
            self.run_dump(S, out, 'off')
            self.assertFalse(any(f.endswith('.enc') for f in os.listdir(out)))

    def test_no_secret_in_logs_or_manifest(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out:
            m, text = self.run_dump(S, out, 'on')
            self.assertNotIn(PW, text)
            self.assertNotIn(PW, T.slurp(os.path.join(out, 'manifest.json'), 'r', encoding='utf-8'))
            self.assertNotIn(PW, json.dumps(S.F.log_rows))

    def test_the_check_command_writes_nothing(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as w:
            self.run_dump(S, enc, 'on')
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(bc.main(['check', enc], env=ENV), 0)
                self.assertEqual(bc.main(['check', enc], env={'BACKUP_PASSPHRASE': PW2}), 1)
            self.assertEqual(os.listdir(w), [])

    def test_passphrase_file_is_supported(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as enc, tempfile.TemporaryDirectory() as w:
            self.run_dump(S, enc, 'on')
            pf = os.path.join(w, 'pp.txt')
            with open(pf, 'w', encoding='utf-8') as f:
                f.write(PW + '\n')
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(bc.main(['check', enc, '--passphrase-file', pf], env={}), 0)

    def test_decrypting_a_plain_backup_is_refused(self):
        with T.FakeServer() as S, tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as plain:
            self.run_dump(S, out, 'off')
            with self.assertRaises(bc.CryptoError):
                bc.decrypt_dir(out, plain, keys())


if __name__ == '__main__':
    unittest.main()
