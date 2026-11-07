#!/bin/bash
# Shared command parsing for the PreToolUse git and gh hooks.
#
# A hook runs with its own cwd, which is not the directory the tool call ran
# in, so the repo has to be recovered from the payload and the command text.
# Several hooks need the same answer, so they share this one parser.
#
# The parser splits the command into shell words with Python's shlex, so a
# quoted path, a quoted message, or heredoc text is never read as a git call.
# It then replays the chain in order:
#   - `cd <path>`, `cd -`, and `cd` move the directory, and a `( ... )`
#     subshell restores it on close
#   - `VAR=value` on its own sets a variable a later `cd "$VAR"` expands
#   - `git -C <path>`, `--git-dir=<path>`, and `--work-tree=<path>` name the
#     repo for that one call, relative to the directory at that point
# The starting directory is the tool call's cwd, since a worktree runs from
# the worktree while CLAUDE_PROJECT_DIR stays on the main checkout. Without
# one it is CLAUDE_PROJECT_DIR, then the hook's own cwd.

# The words come back NUL-separated: a quoted commit message may hold newlines.
# It prints the matched subcommand, the repo dir, then that call's arguments.
_GIT_PARSE_PY='
import os, re, shlex, sys

base, want = sys.argv[1], sys.argv[2]
wanted = set(want.split("|")) if want else None
cmd = sys.stdin.read()
base = base or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
home = os.environ.get("HOME", "")

def strip_heredocs(text):
    out, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for delim in re.findall(r"(?<!<)<<(?!<)-?\s*[\x27\"]?(\w+)[\x27\"]?", line):
            while i < len(lines) and lines[i].strip() != delim:
                i += 1
            i += 1
    return "\n".join(out)

text = strip_heredocs(cmd).replace("\\\n", " ")
ops = ";&|()\n"
lex = shlex.shlex(text, posix=True, punctuation_chars=ops)
lex.whitespace = " \t\r"
lex.whitespace_split = True
words = list(lex)

variables = {}

def expand(word):
    if word == "~":
        word = home
    elif word.startswith("~/"):
        word = home + word[1:]
    def var(m):
        name = m.group(1) or m.group(2)
        return variables.get(name, os.environ.get(name, m.group(0)))
    return re.sub(r"\$\{(\w+)\}|\$(\w+)", var, word)

def resolve(cur, path):
    path = expand(path)
    return os.path.normpath(path if path.startswith("/") else os.path.join(cur, path))

ASSIGN = re.compile(r"^[A-Za-z_]\w*=")
WRAPPERS = {"env", "command", "exec", "time", "nohup", "builtin"}
GIT_VALUE_OPTS = {"-c", "--namespace", "--exec-path", "--config-env", "--super-prefix", "--list-cmds"}

cur, prev, stack = base, base, []
match = None

def run(cmd_words):
    global cur, prev, match
    w = list(cmd_words)
    if w and all(ASSIGN.match(x) for x in w):
        for x in w:
            name, _, value = x.partition("=")
            variables[name] = expand(value)
        return
    wrapped = False
    while w and (ASSIGN.match(w[0]) or w[0] in WRAPPERS or (wrapped and w[0].startswith("-"))):
        wrapped = wrapped or w[0] in WRAPPERS
        w.pop(0)
    if not w:
        return
    prog = os.path.basename(w[0])
    if prog in ("cd", "pushd"):
        args = [x for x in w[1:] if x not in ("-L", "-P", "--")]
        if not args:
            target = home
        elif args[0] == "-":
            target = prev
        else:
            target = resolve(cur, args[0])
        prev, cur = cur, target
        return
    if prog == "gh" and wanted is None:
        match = ("gh", cur, w[1:])
        return
    if prog != "git":
        return
    d, work, gitdir, i = cur, None, None, 1
    while i < len(w):
        x = w[i]
        if x == "-C" and i + 1 < len(w):
            d = resolve(d, w[i + 1])
            i += 2
        elif x in ("--git-dir", "--work-tree") and i + 1 < len(w):
            if x == "--git-dir":
                gitdir = resolve(d, w[i + 1])
            else:
                work = resolve(d, w[i + 1])
            i += 2
        elif x.startswith("--git-dir="):
            gitdir = resolve(d, x.split("=", 1)[1])
            i += 1
        elif x.startswith("--work-tree="):
            work = resolve(d, x.split("=", 1)[1])
            i += 1
        elif x in GIT_VALUE_OPTS and i + 1 < len(w):
            i += 2
        elif x.startswith("-"):
            i += 1
        else:
            break
    if i >= len(w):
        return
    sub = w[i]
    if wanted is not None and sub not in wanted:
        return
    if work:
        repo = work
    elif gitdir:
        repo = os.path.dirname(gitdir) if os.path.basename(gitdir) == ".git" else gitdir
    else:
        repo = d
    match = (sub, repo, w[i + 1:])

pending = []
for tok in words:
    if set(tok) <= set(ops):
        run(pending)
        pending = []
        for ch in tok:
            if ch == "(":
                stack.append((cur, prev))
            elif ch == ")" and stack:
                cur, prev = stack.pop()
    else:
        pending.append(tok)
run(pending)

sub, repo, args = match if match else ("", cur, [])
if sub == "gh":
    sub = ""
sys.stdout.write("".join(f + "\0" for f in [sub, repo] + args))
'

# parse_git_command <command> <cwd> [subcommand[|subcommand...]]
# Sets GIT_SUB to the matched subcommand, or empty when the command runs no
# such git call; GIT_REPO_DIR to the repo of the last matching call; and
# GIT_ARGS to that call's arguments. With no subcommand, the last git or gh
# call matches, and a gh call leaves GIT_SUB empty with its words in GIT_ARGS. Without a match,
# GIT_REPO_DIR is the directory the chain ends in. Succeeds when GIT_SUB is set.
parse_git_command() {
  local field n=0
  GIT_SUB=""
  GIT_REPO_DIR=""
  GIT_ARGS=()
  while IFS= read -r -d '' field; do
    case $n in
      0) GIT_SUB=$field ;;
      1) GIT_REPO_DIR=$field ;;
      *) GIT_ARGS+=("$field") ;;
    esac
    n=$((n + 1))
  done < <(printf '%s' "$1" | python3 -c "$_GIT_PARSE_PY" "$2" "${3:-}" 2>/dev/null)

  # Unbalanced quotes or no python3: a substring match keeps the gates on
  # rather than letting the call through ungated.
  if [ "$n" -lt 2 ]; then
    GIT_REPO_DIR="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
    local sub IFS='|'
    for sub in ${3:-}; do
      case "$1" in
        *"git $sub"*|*"git -C "*" $sub"*) GIT_SUB=$sub; break ;;
      esac
    done
  fi
  [ -n "$GIT_SUB" ]
}

# git_runs <command> <subcommand[|subcommand...]>
# Succeeds when the command runs one of the git subcommands, in any form:
# `git -C <dir>`, `git -c k=v`, `git --no-pager`, or behind env assignments.
git_runs() {
  case "$1" in
    *git*) parse_git_command "$1" "" "$2" ;;
    *) return 1 ;;
  esac
}

# git_args_ask_help: succeeds when the matched call asks for --help or -h,
# which only prints usage and so needs no gate.
git_args_ask_help() {
  case " ${GIT_ARGS[*]} " in
    *" --help "*|*" -h "*) return 0 ;;
  esac
  return 1
}

# resolve_repo_dir <command> <payload-cwd> [subcommand]
# Prints an absolute directory. Never fails: a garbled parse yields a path
# that does not resolve, and every caller handles that.
resolve_repo_dir() {
  parse_git_command "$@"
  printf '%s\n' "$GIT_REPO_DIR"
}
