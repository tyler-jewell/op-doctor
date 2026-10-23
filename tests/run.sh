#!/usr/bin/env bash
# Test suite for op-doctor. No external frameworks. Run: bash tests/run.sh
# All "secrets" are random sentinels generated at run time; nothing secret-like is committed.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BIN="$ROOT/bin/op-doctor"
T=$(mktemp -d "${TMPDIR:-/tmp}/op-doctor-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }
eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$2', got '$1')"; fi; }
has() { if printf '%s' "$1" | grep -Fq -- "$2"; then ok; else bad "$3 (missing '$2')"; fi; }
hasnt() { if printf '%s' "$1" | grep -Fq -- "$2"; then bad "$3 (unexpected '$2')"; else ok; fi; }
jqok() { if printf '%s' "$1" | jq -e "$2" >/dev/null 2>&1; then ok; else bad "$3 (jq: $2)"; fi; }

# isolate from the real environment
export HOME="$T/home"; mkdir -p "$HOME"
export XDG_CONFIG_HOME="$T/xdg"; mkdir -p "$XDG_CONFIG_HOME"
unset OP_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST OP_CONNECT_TOKEN NO_COLOR
export PATH="$T/bin:$PATH"; mkdir -p "$T/bin"
cp "$HERE/fixtures/op" "$T/bin/op"; chmod +x "$T/bin/op"
export FAKE_OP_DIR="$T/fake"; export FAKE_OP_LOG="$T/op.log"
ALL="$T/all.out"; : > "$ALL"

rnd() { printf 'sentinel-%s' "$(od -An -N10 -tx1 /dev/urandom | tr -d ' \n')"; }
S_PW=$(rnd); S_PIN=$(rnd); S_TOK=$(rnd); S_DEV=$(rnd); S_FLAKY=$(rnd)
PLAIN=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')   # plaintext "secret" for lint tests
PLAIN2=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

# ---- fake 1Password contents
mkitem() { # vault item json
  mkdir -p "$FAKE_OP_DIR/vaults/$1"; printf '%s\n' "$3" > "$FAKE_OP_DIR/vaults/$1/$2.json"
}
mkdir -p "$FAKE_OP_DIR/vaults/denied-vault"; printf 'denied-vault\n' > "$FAKE_OP_DIR/denied"
mkitem v1 db "$(jq -n --arg pw "$S_PW" --arg pin "$S_PIN" '{title:"db",fields:[
  {id:"password",label:"password",type:"CONCEALED",value:$pw},
  {id:"notes",label:"notes",type:"STRING",value:""},
  {id:"pin1",label:"pin",type:"CONCEALED",value:$pin,section:{id:"s1",label:"sec1"}}],files:[]}')"
mkitem v1 api "$(jq -n --arg t "$S_TOK" '{title:"api",fields:[{id:"token",label:"token",type:"CONCEALED",value:$t}]}')"
mkitem v1 flaky "$(jq -n --arg t "$S_FLAKY" '{title:"flaky",fields:[{id:"key",label:"key",type:"CONCEALED",value:$t}]}')"
mkitem dev db "$(jq -n --arg t "$S_DEV" '{title:"db",fields:[{id:"password",label:"password",type:"CONCEALED",value:$t}]}')"
mkdir -p "$FAKE_OP_DIR/vaults/other"

# ---- fixture repos
mkrepo() { mkdir -p "$1"; git -C "$1" init -q -b main; git -C "$1" config user.email t@example.invalid; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }
commit() { git -C "$1" add -A; git -C "$1" commit -q -m init; }

A="$T/repos/repo-a"; mkrepo "$A"
cat > "$A/op.refs" <<'EOF'
# references only
DB_PASSWORD=op://v1/db/password
API_TOKEN=op://v1/api/token
EMPTY_NOTE=op://v1/db/notes
NO_FIELD=op://v1/db/nofield
NO_ITEM=op://v1/ghost/password
NO_VAULT=op://nov/db/password
NO_VAULT2=op://nov/other/password
DENIED=op://denied-vault/x/y
VAR_REF=op://$ENVV/db/password
UNRESOLVED=op://$NOPE_VAR/db/password
WITH_SECTION="op://v1/db/sec1/pin"
TYPE_ATTR=op://v1/db/password?attribute=type
EOF
printf 'OTHER_PW=op://v1/db/password\n' > "$A/other.op.env"
printf 'Example: op://example-vault/example-item/field and op://<vault>/x/y\nignored op://bad op-doctor:ignore\n' > "$A/README.md"
mkdir -p "$A/.op"; printf 'FROM_DIR=op://v1/api/token\n' > "$A/.op/extra"
printf 'PLAIN=%s\nUNTRACKED_REF=op://v1/db/password\n' "$PLAIN" > "$A/.env"
printf '.env\n' > "$A/.gitignore"
commit "$A"

B="$T/repos/repo-b"; mkrepo "$B"
printf 'DB_PASSWORD=%s\nHOST=localhost\n' "$PLAIN" > "$B/.env"
printf 'DB_PASSWORD=changeme\n' > "$B/.env.example"
printf 'API_TOKEN=%s\nBLOB=%s\nBAD=op://onlyvault\nBAD2=op://v/i/f?bogus=1\nOK=op://v1/db/password\nREF2=op://$OP_VAULT/db/password\nVAULT_FREE=\n' "$PLAIN2" "$PLAIN$PLAIN2" > "$B/op.refs"
printf 'KEEP=op://v1/api/token\n' > "$B/.env.op"
commit "$B"

C="$T/repos/repo-c"; mkrepo "$C"; echo "nothing here" > "$C/README.md"; commit "$C"

csum() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum | shasum | cut -d' ' -f1); }
SUM_A=$(csum "$A"); SUM_B=$(csum "$B"); SUM_C=$(csum "$C")

run() { # -> OUT, ERR, RC ; also appended to ALL for the no-value test
  OUT=$("$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
  printf '%s\n%s\n' "$OUT" "$ERR" >> "$ALL"
}

echo "== basics"
run "$BIN" --version; eq "$RC" 0 "version rc"; has "$OUT" "op-doctor 0." "version text"
run "$BIN" --help; eq "$RC" 0 "help rc"; has "$OUT" "EXIT CODES" "help sections"; has "$OUT" "COMMANDS" "help sections"
run "$BIN"; eq "$RC" 64 "no command is usage error"
run "$BIN" frobnicate; eq "$RC" 64 "unknown command"
run "$BIN" scan --bogus; eq "$RC" 64 "unknown option"
run "$BIN" check --max-requests abc; eq "$RC" 64 "bad max-requests"
run "$BIN" check --token abc; eq "$RC" 64 "secrets via flags rejected"
hasnt "$OUT$ERR" "abc" "rejected secret not echoed"
run "$BIN" check --var 'novalue'; eq "$RC" 64 "bad --var"

echo "== scan"
run "$BIN" scan "$A"; eq "$RC" 0 "scan rc"
has "$OUT" "DB_PASSWORD" "scan lists var"; has "$OUT" "v1/db/password" "scan parsed"
has "$OUT" "FROM_DIR" "scan finds .op/ files"; has "$OUT" "OTHER_PW" "scan finds *.op.env"
hasnt "$OUT" "UNTRACKED_REF" "scan skips untracked/ignored files"
hasnt "$OUT" "op://bad" "op-doctor:ignore honoured"
run "$BIN" scan --json "$A"; J=$OUT
jqok "$J" '.schema=="op-doctor/v1" and .command=="scan" and .exit_code==0' "json envelope"
jqok "$J" '[.references[]|select(.variable=="DB_PASSWORD")][0]|.vault=="v1" and .item=="db" and .field=="password" and .parse=="ok"' "json parsed ref"
jqok "$J" '[.references[]|select(.variable=="WITH_SECTION")][0]|.section=="sec1" and .field=="pin"' "section parsed"
jqok "$J" '[.references[]|select(.variable=="TYPE_ATTR")][0]|.query=="attribute=type"' "query parsed"
jqok "$J" '(.roots|length)==1 and .roots[0].status=="scanned" and (.checks|length)==0 and .plan==null' "json other keys present"
jqok "$J" 'all(.references[]; has("root") and has("file") and has("line") and has("variable") and has("ref"))' "reference keys"

echo "== lint"
run "$BIN" lint "$B"; eq "$RC" 2 "lint errors -> 2"
has "$OUT" "L002" "plaintext .env flagged"; has "$OUT" "L003" "secret-like value flagged"
has "$OUT" "L001" "malformed flagged"; has "$OUT" "[API_TOKEN]" "key named"; has "$OUT" "[BLOB]" "entropy flagged"
hasnt "$OUT" ".env.example" "example file not flagged"
hasnt "$OUT" ".env.op" "env.op not flagged"
hasnt "$OUT" "[VAULT_FREE]" "empty value ok"
hasnt "$OUT" "[OK]" "ref value ok"
has "$OUT" "op run --env-file=op.refs" "hint present"
run "$BIN" lint --json "$B"
jqok "$OUT" '[.findings[]|select(.code=="L002")]|length==1' "L002 once (.env only)"
jqok "$OUT" '[.findings[]|select(.code=="L001")]|length==2' "two malformed"
jqok "$OUT" '[.findings[]|select(.code=="L003" and .file==".env")]|length==1' "L003 in .env"
run "$BIN" lint "$A"; eq "$RC" 0 "repo-a lint clean (untracked .env ignored)"
run "$BIN" lint --public "$B"; has "$OUT" "L004" "public hardcoded vault warning"
run "$BIN" lint --public --json "$A"; jqok "$OUT" '([.findings[]|select(.code=="L004")]|length>0) and all(.findings[]|select(.code=="L004"); .severity=="warning")' "L004 is warning"
run "$BIN" lint --quiet "$C"; eq "$RC" 0 "clean repo rc"; eq "$OUT" "" "quiet prints nothing when clean"

echo "== check: states"
: > "$FAKE_OP_LOG"
export ENVV=dev
run "$BIN" check --json "$A"; J=$OUT; eq "$RC" 2 "check with problems -> 2"
st() { printf '%s' "$J" | jq -r --arg r "$1" '.checks[]|select(.ref==$r)|.state'; }
eq "$(st 'op://v1/db/password')" ok "state ok"
eq "$(st 'op://v1/db/notes')" empty "state empty"
eq "$(st 'op://v1/db/nofield')" missing-field "state missing-field"
eq "$(st 'op://v1/ghost/password')" missing-item "state missing-item"
eq "$(st 'op://nov/db/password')" missing-vault "state missing-vault"
eq "$(st 'op://denied-vault/x/y')" denied "state denied"
eq "$(st 'op://$NOPE_VAR/db/password')" unresolved-variable "unresolved variable"
eq "$(st 'op://$ENVV/db/password')" ok "variable from environment"
eq "$(st 'op://v1/db/sec1/pin')" ok "section field"
eq "$(st 'op://v1/db/password?attribute=type')" ok "query attr"
eq "$(st 'op://v1/api/token')" ok "api token"
jqok "$J" '.summary.states|keys|length==8' "all 8 states in summary"
jqok "$J" '.summary.states.ok>=5 and .summary.states.empty==1 and .summary.states["unresolved-variable"]==1' "summary counts"
jqok "$J" '(.checks[]|select(.ref=="op://v1/db/password")|.locations|length)>=2' "locations merged across files"

echo "== check: frugal requests"
n_get=$(grep -c '^item-get' "$FAKE_OP_LOG"); n_read=$(grep -c '^read' "$FAKE_OP_LOG")
# 8 groups (README example included); nov/other is skipped because the missing vault nov is cached after nov/db
eq "$n_get" 7 "one item get per distinct vault+item (and vault failures cached)"
eq "$n_read" 0 "no read fallbacks needed"
eq "$(grep -c 'v1 db' "$FAKE_OP_LOG")" 1 "v1/db fetched once despite many refs"
run "$BIN" check --dry-run --json "$A"; eq "$RC" 0 "dry-run rc"
jqok "$OUT" '.dry_run==true and .plan.items==8 and .plan.requests_estimated==24' "dry-run plan"
: > "$FAKE_OP_LOG"; run "$BIN" check --dry-run "$A"; eq "$(wc -c < "$FAKE_OP_LOG" | tr -d ' ')" 0 "dry-run calls nothing"
has "$OUT" "24 API request" "dry-run human"
run "$BIN" check --max-requests 5 "$A"; eq "$RC" 64 "max-requests guard"
has "$ERR" "max-requests" "guard message"
printf 'F=op://v1/flaky/key\n' > "$T/fl.refs"; FL="$T/repos/repo-fl"; mkrepo "$FL"; cp "$T/fl.refs" "$FL/op.refs"; commit "$FL"
: > "$FAKE_OP_LOG"; FAKE_OP_ITEMGET_FAIL=flaky run "$BIN" check --json "$FL"
eq "$RC" 0 "fallback to op read works"; eq "$(printf '%s' "$OUT" | jq -r '.checks[0].state')" ok "fallback state ok"
eq "$(grep -c '^read' "$FAKE_OP_LOG")" 1 "one read in fallback"
: > "$FAKE_OP_LOG"; run "$BIN" check --method read --json "$FL"; eq "$RC" 0 "--method read"; eq "$(grep -c '^item-get' "$FAKE_OP_LOG")" 0 "read mode does not item-get"
run "$BIN" check --var 'NOPE_VAR=dev' --json "$A"; J=$OUT
eq "$(st 'op://$NOPE_VAR/db/password')" ok "--var supplies variable"
run "$BIN" check --var 'API_TOKEN=x' --json "$A"
export OP_TOKEN_LIKE=1
SECV="$T/repos/repo-sv"; mkrepo "$SECV"; printf 'X=op://$MY_TOKEN/db/password\n' > "$SECV/op.refs"; commit "$SECV"
MY_TOKEN=v1 run "$BIN" check --json "$SECV"; eq "$(printf '%s' "$OUT" | jq -r '.checks[0].state')" unresolved-variable "secret-like variable names refused"
has "$OUT" "refused secret-like variable name" "refusal detail"

echo "== check: op unavailable"
touch "$FAKE_OP_DIR/signed_out"
run "$BIN" check "$A"; eq "$RC" 3 "signed out -> 3"; has "$ERR" "OP_SERVICE_ACCOUNT_TOKEN" "hint mentions service account"
run "$BIN" doctor --json "$B"; eq "$RC" 3 "doctor: op down beats lint errors (3 > 2)"
jqok "$OUT" '.errors|map(.code)|index("op-unavailable")!=null' "json errors op-unavailable"
OP_SERVICE_ACCOUNT_TOKEN=ops_fake_token_value run "$BIN" check "$A"; eq "$RC" 3 "signed out with token (detected from first call)"
hasnt "$OUT$ERR" "ops_fake_token_value" "token never printed"
rm "$FAKE_OP_DIR/signed_out"
touch "$FAKE_OP_DIR/ratelimited"; run "$BIN" check "$A"; eq "$RC" 3 "rate limited -> 3"; rm "$FAKE_OP_DIR/ratelimited"
PATH_NO_OP=$(echo "$PATH" | tr ':' '\n' | grep -vx "$T/bin" | paste -sd: -)
OUT=$(PATH="$PATH_NO_OP" "$BIN" check "$A" 2>&1); RC=$?
if command -v op >/dev/null 2>&1; then ok; else eq "$RC" 3 "missing op -> 3"; fi

echo "== doctor"
run "$BIN" doctor "$C"; eq "$RC" 0 "doctor clean"; has "$OUT" "summary:" "doctor summary"
run "$BIN" doctor --json "$B"; jqok "$OUT" '.command=="doctor" and (.findings|length)>0' "doctor json has lint+checks"

echo "== roots"
printf '# list\n%s\n%s\n' "$A" "$B" > "$T/roots.txt"
run "$BIN" roots --roots "$T/roots.txt"; eq "$RC" 0 "roots rc"; has "$OUT" "repo-a" "roots lists a"; has "$OUT" "2 root(s)" "two roots"
run "$BIN" scan --roots "$T/roots.txt" --exclude '*repo-b*' --json; jqok "$OUT" '([.roots[]|select(.status=="excluded")]|length)==1 and .summary.roots==1' "exclude works"
mkdir -p "$XDG_CONFIG_HOME/op-doctor"; printf '# c\n%s\n%s\n' "$A" "$C" > "$XDG_CONFIG_HOME/op-doctor/roots"
run "$BIN" roots --all; has "$OUT" "repo-c" "--all reads roots file"
printf 'exclude = *repo-c*\n' > "$XDG_CONFIG_HOME/op-doctor/config"
run "$BIN" roots --all; hasnt "$OUT" "repo-c " "config exclude honoured"
run "$BIN" roots --all --json; jqok "$OUT" '([.roots[]|select(.status=="excluded")]|length)==1' "config exclude in json"
printf 'bogus line\n' > "$XDG_CONFIG_HOME/op-doctor/config"; run "$BIN" roots --all; eq "$RC" 4 "invalid config -> 4"
rm "$XDG_CONFIG_HOME/op-doctor/config" "$XDG_CONFIG_HOME/op-doctor/roots"
mkdir -p "$XDG_CONFIG_HOME/dotfiles"; printf '# m\nex/a %s role yes\nex/c %s role yes exempt\nex/z %s/missing role yes\n' "$A" "$C" "$T" > "$XDG_CONFIG_HOME/dotfiles/repos.txt"
run "$BIN" roots --all; has "$OUT" "repo-a" "manifest dest used"; has "$OUT" "2 root(s)" "missing manifest dest skipped"
rm -r "$XDG_CONFIG_HOME/dotfiles"
mkdir -p "$HOME/workspaces"; cp -R "$C" "$HOME/workspaces/ws-one"
run "$BIN" roots --all; has "$OUT" "ws-one" "fallback to ~/workspaces/*"
run "$BIN" scan "$T/nonexistent"; eq "$RC" 4 "invalid root -> 4"
run "$BIN" scan "$T"; eq "$RC" 4 "non-git dir -> 4"
(cd "$A/.op" && "$BIN" scan >/dev/null 2>&1; echo $? > "$T/sub.rc"); eq "$(cat "$T/sub.rc")" 0 "default root = current repo from subdir"
printf 'public = maybe\n' > "$B/.op-doctor"; run "$BIN" lint "$B"; eq "$RC" 4 "bad per-repo config -> 4"; rm "$B/.op-doctor"
run "$BIN" lint "$A" "$T/nonexistent"; eq "$RC" 4 "mixed ok+invalid root -> 4 (4 > 2)"
printf 'ignore = op.refs\n' > "$C/.op-doctor"; cp "$B/op.refs" "$C/op.refs"; git -C "$C" add op.refs
run "$BIN" lint "$C"; eq "$RC" 0 "per-repo ignore skips file"
git -C "$C" rm -q -f --cached op.refs; rm -f "$C/op.refs" "$C/.op-doctor"

echo "== hooks"
run bash "$ROOT/contrib/pre-commit-op-lint"; RC0=$RC
(cd "$B" && OUT=$(bash "$ROOT/contrib/pre-commit-op-lint" 2>&1); echo "$?" > "$T/hook.rc"); eq "$(cat "$T/hook.rc")" 2 "pre-commit hook fails on lint errors"
(cd "$A" && OUT=$(bash "$ROOT/contrib/pre-commit-op-lint" 2>&1); echo "$?" > "$T/hook.rc"); eq "$(cat "$T/hook.rc")" 0 "pre-commit hook passes on clean repo"

echo "== guarantees"
eq "$(csum "$A")" "$SUM_A" "repo-a unchanged (read-only)"
eq "$(csum "$B")" "$SUM_B" "repo-b unchanged (read-only)"
git -C "$C" status --porcelain | grep -q . && bad "repo-c dirty" || ok
leaks=0
for s in "$S_PW" "$S_PIN" "$S_TOK" "$S_DEV" "$S_FLAKY" "$PLAIN" "$PLAIN2"; do
  grep -Fq -- "$s" "$ALL" && { bad "value leaked into output: ${s:0:0}(redacted)"; leaks=1; }
done
[ "$leaks" = 0 ] && ok
# make sure the test is not vacuous: the shim does emit the sentinel
"$T/bin/op" item get db --vault v1 --format json | grep -Fq "$S_PW" && ok || bad "shim sanity"
[ -s "$ALL" ] && ok || bad "outputs captured"

echo
printf 'passed: %s  failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
