#!/bin/bash
# Shared PR body extraction for the `gh pr` hooks.
#
# Two hooks read the same body out of one command string: the prose gate lints
# its wording, the body gate checks it against rules/git-conventions.md. The
# parse lives here once so both hooks read the same body.
#
# Handles the three shapes gh accepts: `--body-file <path>`, a `--body`
# heredoc, and a quoted `--body` / `-b` value. A command with no body prints
# nothing, which every caller already treats as "nothing to check".
#
# extract_api_body reads the `body=` field of a `gh api` call for the reply
# gate. Both extractors share the heredoc reader below.

# Python prepended to each extractor. heredoc(cmd, start) returns the body of
# the first heredoc opened at or after start, or None. The body ends at its
# delimiter, not at the end of the command, so a later flag on the same line
# never gets read as prose.
_PR_BODY_HEREDOC='
import re, sys

def heredoc(cmd, start):
    m = re.compile(r"<<-?[\x27\"]?(\w+)[\x27\"]?").search(cmd, start)
    if not m:
        return None
    after = cmd[m.end():]
    nl = after.find("\n")
    if nl == -1:
        return None
    out = []
    for line in after[nl + 1:].split("\n"):
        if line.strip() == m.group(1):
            break
        out.append(line)
    return "\n".join(out)
'

# pr_body_files <command> [strict]
# Prints the --body-file / -F path, one per line, or nothing when the command
# uses no such flag. Every gh pr and gh issue subcommand spells --body-file as
# -F. A "$f" path resolves through `f=<path>` or `for f in <paths>; do` earlier
# in the same command, so a loop posting several bodies prints each file. A
# glob prints nothing, because the hook would expand it before the command
# runs. With strict, a file the command also names elsewhere prints nothing
# too, since the command may write it after the hook reads it.
pr_body_files() {
  printf '%s' "$1" | STRICT="${2:-}" python3 -c '
import glob, os, re, shlex, sys
cmd = sys.stdin.read()
strict = os.environ.get("STRICT") == "strict"
m = re.search(r"(?:^|\s)(?:--body-file|-F)[=\s]+[\x27\"]?([^\x27\"\s]+)", cmd)
if not m:
    sys.exit(0)
path = m.group(1)
rest = cmd[:m.start(1)] + cmd[m.end(1):]

def literal(word):
    if strict and word in rest:
        return None
    word = os.path.expanduser(os.path.expandvars(word))
    if re.search(r"[$`]", word) or glob.has_magic(word):
        return None
    return [word]

v = re.fullmatch(r"\$\{?(\w+)\}?", path)
words = [path]
if v:
    before = cmd[:m.start()]
    name = re.escape(v.group(1))
    sources = list(re.finditer(r"\bfor\s+%s\s+in\s+([^;\n]*?)\s*[;\n]\s*do\b" % name, before))
    sources += re.finditer(r"(?:^|[\s;&|(])%s=(\x22[^\x22]*\x22|\x27[^\x27]*\x27|[^\s;&|]+)" % name, before)
    last = max(sources, key=lambda s: s.start(), default=None)
    if last:
        try:
            words = shlex.split(last.group(1))
        except ValueError:
            pass
        else:
            rest = cmd[:last.start(1)] + cmd[last.end(1):]
paths = []
for word in words:
    found = literal(word)
    if found is None:
        sys.exit(0)
    paths += found
print("\n".join(paths))
' 2>/dev/null
}

# pr_command_segment <command>
# Prints only the gh pr or gh issue calls in the command, without the commands
# chained before or after them, so text in a neighbouring command cannot block
# a PR. Prints the whole command when the shell quoting cannot be parsed.
pr_command_segment() {
  printf '%s' "$1" | python3 -c '
import shlex, sys
# A backslash before a newline continues the line, so it never separates commands.
cmd = sys.stdin.read().replace("\\\n", " ")
ops = set(";&|()\n")
try:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars="".join(ops))
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    tokens = list(lex)
except ValueError:
    print(cmd)
    sys.exit(0)
segments, current = [], []
for tok in tokens + [";"]:
    if tok and set(tok) <= ops:
        if any(current[i:i + 3] in (["gh", k, s] for k in ("pr", "issue") for s in ("create", "edit"))
               for i in range(len(current))):
            segments.append(" ".join(current))
        current = []
    else:
        current.append(tok)
print("\n".join(segments) if segments else cmd)
' 2>/dev/null
}

# extract_pr_body <command>
# Prints the body text the command would send.
extract_pr_body() {
  local command="$1" body_files f all=1

  body_files=$(pr_body_files "$command")
  if [ -n "$body_files" ]; then
    while IFS= read -r f; do [ -f "$f" ] || all=0; done <<< "$body_files"
    if [ "$all" -eq 1 ]; then
      while IFS= read -r f; do cat -- "$f"; echo; done <<< "$body_files"
      return 0
    fi
  fi

  printf '%s' "$command" | python3 -c "$_PR_BODY_HEREDOC"'
cmd = sys.stdin.read()

m = re.search(r"--body[=\s]+(?=<<)", cmd)
if m:
    body = heredoc(cmd, m.end())
    if body is not None:
        print(body)
        sys.exit(0)

# The backreference keeps a quote of the other kind inside the body from
# ending the match early.
vals = [m.group(2) for m in
        re.finditer(r"(?:-b|--body)[=\s]+([\x27\"])(.*?)\1", cmd, re.S)]
if vals:
    print("\n".join(vals))
' 2>/dev/null
}

# extract_api_body <command>
# Prints the body= field a `gh api` call sends: a quoted or bare -f value, a
# -F @file read relative to the current dir, or a -F @- heredoc. Prints
# nothing when the call has no body field.
extract_api_body() {
  printf '%s' "$1" | python3 -c "$_PR_BODY_HEREDOC"'
cmd = sys.stdin.read()
m = re.search(r"(?:^|\s)(-f|-F|--field|--raw-field)[=\s]+"
              r"(?:([\x27\"])body=(.*?)\2|body=(?:([\x27\"])(.*?)\4|(\S+)))", cmd, re.S)
if m:
    if m.group(2):
        val = m.group(3)
    elif m.group(4):
        val = m.group(5)
    else:
        val = m.group(6)
    if m.group(1) in ("-F", "--field") and val.startswith("@"):
        if val == "@-":
            val = heredoc(cmd, m.end()) or ""
        else:
            try:
                val = open(val[1:]).read()
            except OSError:
                val = ""
    print(val)
' 2>/dev/null
}

# extract_pr_title <command>
# Prints the --title / -t value, or nothing when the command sets no title or
# sets one only the shell can expand, such as "$TITLE" or "$(cat title.txt)".
extract_pr_title() {
  printf '%s' "$1" | python3 -c '
import sys, re
cmd = sys.stdin.read()
# A quoted body can mention -t, so drop body values before looking for one.
cmd = re.sub(r"(?:^|\s)(?:-b|--body)[=\s]+([\x27\"])(.*?)\1", " ", cmd, flags=re.S)
m = re.search(r"(?:^|\s)(?:-t|--title)[=\s]+([\x27\"])(.*?)\1", cmd, re.S)
if m:
    quote, title = m.group(1), m.group(2)
else:
    m = re.search(r"(?:^|\s)(?:-t|--title)[=\s]+([^\s\x27\"]+)", cmd)
    quote, title = "", m.group(1) if m else ""
if quote != "\x27" and re.search(r"[$`]", title):
    title = ""
print(title)
' 2>/dev/null
}
