"""X2 storefront packaging tests (tools/build_site.py): the config guard refuses secrets, the lint finds forbidden words and foreign hosts.
Run: python3 tests/py/test_build_site.py   (no network; uses temporary folders)"""
import base64
import importlib.util
import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = importlib.util.spec_from_file_location('build_site', os.path.join(ROOT, 'tools', 'build_site.py'))
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

PASS = FAIL = 0


def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print('FAIL ' + name)


def jwt(role):
    h = base64.urlsafe_b64encode(b'{"alg":"HS256"}').decode().rstrip('=')
    p = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
    return h + '.' + p + '.sig'


# config guard
check('publishable key is accepted', bs.check_config({'url': 'https://rpqrcmesbhwtyrikabhy.supabase.co', 'key': 'sb_publishable_abc'}) is True)
check('anon JWT (role anon) is accepted', bs.check_config({'url': 'https://rpqrcmesbhwtyrikabhy.supabase.co', 'key': jwt('anon')}) is True)
check('a secret key is refused', bs.check_config({'url': 'https://rpqrcmesbhwtyrikabhy.supabase.co', 'key': 'sb_secret_xyz'}) is False)
check('a service_role JWT is refused', bs.check_config({'url': 'https://rpqrcmesbhwtyrikabhy.supabase.co', 'key': jwt('service_role')}) is False)
check('a non-https project URL is refused', bs.check_config({'url': 'http://example.com', 'key': 'sb_publishable_abc'}) is False)
check('localhost preview URL is allowed for testing', bs.check_config({'url': 'http://localhost:8000', 'key': 'sb_publishable_abc'}) is True)
check('a broken JWT does not crash the guard', bs.jwt_role('not.a.jwt') is None)

# lint
tmp = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(tmp, 'assets'))
    with open(os.path.join(tmp, 'index.html'), 'w') as f:
        f.write('<html>ok https://schema.org/Product https://wa.me/1</html>')
    with open(os.path.join(tmp, 'assets', 'a.js'), 'w') as f:
        f.write('var x = 1;')
    check('clean folder passes the lint', bs.lint(tmp) is True)
    with open(os.path.join(tmp, 'assets', 'b.js'), 'w') as f:
        f.write('var k = "service_role";')
    check('a service_role word is caught', bs.lint(tmp) is False)
    os.remove(os.path.join(tmp, 'assets', 'b.js'))
    with open(os.path.join(tmp, 'assets', 'c.js'), 'w') as f:
        f.write('fetch("https://tracker.example.org/x")')
    check('an unexpected external host is caught', bs.lint(tmp) is False)
    os.remove(os.path.join(tmp, 'assets', 'c.js'))
    with open(os.path.join(tmp, 'assets', 'd.js'), 'w') as f:
        f.write('-----BEGIN PRIVATE KEY-----')
    check('a private key block is caught', bs.lint(tmp) is False)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# the real site folder is clean
check('the real site/ folder passes the lint', bs.lint(bs.SITE) is True)

# sitemap has absolute URLs
sm = bs.sitemap('https://example.com', True)
check('sitemap uses the base address and lists the catalogue-free pages', 'https://example.com/catalogue.html' in sm and 'https://example.com/custom-cake.html' in sm)

print('RESULT build_site: %d pass, %d fail' % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
