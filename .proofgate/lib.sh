#!/usr/bin/env bash
# ProofGate shared library — sourced by verify.sh AND by any guard that needs to
# read proofgate.json. The whole point: config access with ZERO hard dependency.
# jq is preferred; when it is absent we fall back to node, then python3; when none
# of the three exists every function degrades to "empty" and the caller keeps its
# own inline default. Nothing here ever hard-fails a gate.
#
# Contract for callers: export/point PROOFGATE_CFG at proofgate.json before use
# (defaults to ./proofgate.json). All functions are safe to call when the file is
# absent — they simply return nothing.
#
# Scars this file carries:
#  - v1 made jq a hard dependency for ALL config and silently ignored proofgate.json
#    on any machine without jq. That is exactly the "works on my box" trap the gate
#    exists to kill, so the gate's own config reader must not have it.

# shellcheck disable=SC2120  # helpers are intentionally callable with no args

_pg_cfg_file() { printf '%s' "${PROOFGATE_CFG:-proofgate.json}"; }

# The node/python walkers parse a RESTRICTED jq path grammar: dotted keys plus
# [N] integer indices (e.g. .commands.typecheck, .smoke[0].url). That is all any
# guard needs; anything fancier should use jq (and degrade to empty without it).
_PG_NODE_WALK='const fs=require("fs");try{const d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const p=String(process.argv[2]).replace(/^\./,"");let c=d;if(p!==""){for(const seg of p.split(".")){const m=seg.match(/^([^\[]*)(?:\[(\d+)\])?$/);if(!m)process.exit(0);if(m[1]!==""){if(c==null)process.exit(0);c=c[m[1].replace(/^"|"$/g,"")];}if(m[2]!==undefined){if(c==null)process.exit(0);c=c[Number(m[2])];}}}if(c==null)process.exit(0);process.stdout.write(typeof c==="object"?JSON.stringify(c):String(c));}catch(e){process.exit(0);}'
_PG_PY_WALK='import sys,json,re
try:
 d=json.load(open(sys.argv[1]));p=sys.argv[2]
 if p[:1]==".":p=p[1:]
 c=d
 if p!="":
  for seg in p.split("."):
   m=re.match(r"^([^\[]*)(?:\[(\d+)\])?$",seg)
   if not m:sys.exit(0)
   k,i=m.group(1),m.group(2)
   if k and k[:1]==chr(34) and k[-1:]==chr(34):k=k[1:-1]
   if k!="":
    if c is None:sys.exit(0)
    c=c.get(k) if isinstance(c,dict) else None
   if i is not None:
    if not isinstance(c,list) or int(i)>=len(c):sys.exit(0)
    c=c[int(i)]
 if c is None:sys.exit(0)
 sys.stdout.write(c if isinstance(c,str) else (json.dumps(c) if isinstance(c,(dict,list)) else ("true" if c is True else "false" if c is False else str(c))))
except Exception:
 sys.exit(0)'

# cfg <jq-path> — print a scalar raw, or a compact JSON string for objects/arrays.
# Empty output when the key is missing, the file is absent, or no parser exists.
cfg() {
  local path="$1" f; f="$(_pg_cfg_file)"
  [ -f "$f" ] || return 0
  if command -v jq >/dev/null 2>&1; then jq -c -r "$path // empty" "$f" 2>/dev/null; return; fi
  if command -v node >/dev/null 2>&1; then node -e "$_PG_NODE_WALK" "$f" "$path" 2>/dev/null; return; fi
  command -v python3 >/dev/null 2>&1 && python3 -c "$_PG_PY_WALK" "$f" "$path" 2>/dev/null
}

# cfg_len <jq-path-to-array> — element count (0 when absent/not an array).
cfg_len() {
  local j; j="$(cfg "$1")"
  [ -z "$j" ] && { printf '0'; return; }
  if command -v jq >/dev/null 2>&1; then printf '%s' "$j" | jq 'if type=="array" then length else 0 end' 2>/dev/null || printf '0'; return; fi
  if command -v node >/dev/null 2>&1; then printf '%s' "$j" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const a=JSON.parse(s);process.stdout.write(String(Array.isArray(a)?a.length:0));}catch(e){process.stdout.write("0");}})' 2>/dev/null || printf '0'; return; fi
  printf '%s' "$j" | python3 -c 'import sys,json
try:
 a=json.load(sys.stdin);print(len(a) if isinstance(a,list) else 0)
except Exception:print(0)' 2>/dev/null || printf '0'
}

# cfg_list <jq-path-to-array> — one scalar per line (objects printed as compact JSON).
cfg_list() {
  local j; j="$(cfg "$1")"
  [ -z "$j" ] && return 0
  if command -v jq >/dev/null 2>&1; then printf '%s' "$j" | jq -r 'if type=="array" then .[] else empty end | if type=="object" or type=="array" then tojson else . end' 2>/dev/null; return; fi
  if command -v node >/dev/null 2>&1; then printf '%s' "$j" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const a=JSON.parse(s);(Array.isArray(a)?a:[]).forEach(x=>console.log(x!==null&&typeof x==="object"?JSON.stringify(x):String(x)));}catch(e){}})' 2>/dev/null; return; fi
  printf '%s' "$j" | python3 -c 'import sys,json
try:
 a=json.load(sys.stdin)
 for x in (a if isinstance(a,list) else []):
  print(json.dumps(x) if isinstance(x,(dict,list)) else x)
except Exception:pass' 2>/dev/null
}

# pg_json_escape <string> — escape a string for embedding in JSON (backslash FIRST).
# Used by verify.sh to hand-write the verdict and by guards that record detail.
pg_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
}

# pg_fingerprint <guard> <file> <line-content> — stable id for suppression.
# Deliberately NOT the line NUMBER (churn-stable): guard name + path + a hash of
# the offending line's text. Mirrors gitleaks' fingerprint idea. Used by
# .proofgateignore, the persistent per-finding false-positive escape hatch.
pg_fingerprint() {
  local guard="$1" file="$2" content="$3" h
  if command -v sha1sum >/dev/null 2>&1; then h="$(printf '%s' "$content" | sha1sum | cut -c1-12)"
  elif command -v shasum >/dev/null 2>&1; then h="$(printf '%s' "$content" | shasum | cut -c1-12)"
  else h="$(printf '%s' "$content" | cksum | tr -d ' ' | cut -c1-12)"; fi
  printf '%s:%s:%s' "$guard" "$file" "$h"
}

# pg_ignored <fingerprint> — is this finding suppressed in .proofgateignore?
# The gate is DIFF-SCOPED (only $BASE..HEAD added lines), so legacy findings never
# pile up the way a full-repo scanner's do — a full baseline/ratchet would be
# over-engineering. What's still needed is a durable escape hatch for a specific
# false positive you can't annotate inline (e.g. a generated file): one fingerprint
# per line in .proofgateignore at the repo root ('#' comments allowed).
pg_ignored() {
  local fp="$1" f="${PROOFGATE_IGNORE:-.proofgateignore}"
  [ -f "$f" ] || return 1
  grep -Fxq -- "$fp" "$f" 2>/dev/null
}

# Pathspecs that keep the gate from flagging its OWN source. Vendoring the guards
# into a consumer repo adds files whose text literally CONTAINS the sin patterns
# (rejectUnauthorized:false, <<<<<<<, key regexes); without this every guard would
# fail the very commit that installs it. (Guards also carry inline `proofgate-allow`
# on their pattern lines; this covers whole-file cases like the tests.)
PG_SELF_EXCLUDE=(':(exclude)*guards.d/*' ':(exclude)*/.proofgate/*' ':(exclude).proofgate/*' ':(exclude)*/scripts/verify.sh' ':(exclude)*/scripts/lib.sh' ':(exclude)*run-tests.sh' ':(exclude)*push-guard.sh' ':(exclude)*stop-guard.sh')

# pg_added_with_file [extra-pathspecs...] — stream "<file>\t<added-line>" for every
# added line in $BASE..HEAD, minus the gate's own files and any line bearing the
# `proofgate-allow` marker. The bedrock every diff guard builds on.
pg_added_with_file() {
  local base="${PROOFGATE_BASE:?PROOFGATE_BASE unset}"
  git diff "$base"..HEAD -- . "${PG_SELF_EXCLUDE[@]}" "$@" 2>/dev/null | awk '
    /^\+\+\+ b\// { f=substr($0,7); next }
    /^\+/ && !/^\+\+\+/ { l=substr($0,2); if (l !~ /proofgate-allow/) print f "\t" l }
  '
}

# pg_scan <guard-name> <ERE> [extra-pathspecs...] — print the file of each added
# line matching the pattern, after self-exclusion, proofgate-allow, AND per-finding
# .proofgateignore suppression. Guards reduce to: count the lines this prints.
pg_scan() {
  local guard="$1" pat="$2"; shift 2
  local tab; tab="$(printf '\t')"
  pg_added_with_file "$@" | while IFS="$tab" read -r file content; do
    printf '%s' "$content" | grep -Eq -- "$pat" || continue     # match CONTENT only, not the path
    pg_ignored "$(pg_fingerprint "$guard" "$file" "$content")" && continue
    printf '%s\n' "$file"
  done
}

# pg_count — count non-empty lines on stdin (the surviving findings from pg_scan).
# NOTE: `grep -c` prints 0 AND exits 1 on no match, so we capture its stdout rather
# than relying on exit status (a naive `grep -c . || echo 0` prints "0\n0").
pg_count() { local n; n="$(grep -c . 2>/dev/null)"; printf '%s' "${n:-0}"; }
