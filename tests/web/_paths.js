// Shared path/port helpers for tests/web/*.js so they run from any directory, in any worktree, in parallel.
//   WEB_DIR   : process.env.WEB_DIR || <this checkout>/web
//   REPO_DIR  : parent of tests/ (data/, supabase/ ...)
//   TESTS_DIR : this directory (what tests receive as argv[2] "SP" - holds smoke.js / stub.js)
//   freePort(): env PORT if set, else a free OS-assigned port (port 0), found synchronously.
const path = require('path');
const TESTS_DIR = __dirname;
const REPO_DIR = path.resolve(__dirname, '..', '..');
const WEB_DIR = process.env.WEB_DIR ? path.resolve(process.env.WEB_DIR) : path.resolve(__dirname, '..', '..', 'web');
process.env.BOS_REPO_DIR = REPO_DIR; // lets smoke.js's data block (eval'd via new Function in many tests) find data/ and supabase/
function freePort() {
  if (process.env.PORT && /^\d+$/.test(process.env.PORT) && Number(process.env.PORT) > 0) return Number(process.env.PORT);
  const out = require('child_process').execFileSync(process.execPath, ['-e', "const s=require('net').createServer().listen(0,()=>{process.stdout.write(String(s.address().port));s.close();})"], { encoding: 'utf8' });
  return Number(out);
}
module.exports = { WEB_DIR, TESTS_DIR, REPO_DIR, freePort };
