#!/bin/bash
# Outbound email scrub.
# PreToolUse hook on Bash, WebFetch and WebSearch. Removes email addresses from
# a call that would send them off the machine: a WebFetch URL, a WebSearch
# query, or a Bash command that names a URL or a network client. The harness
# puts the user's account email in the session context, and a site that asks
# scrapers for a contact address can talk the model into putting it in a
# User-Agent header or a query string.
#
# On Claude Code the hook returns updatedInput with each address replaced by
# redacted@example.invalid, so the call still runs. Permission and deny rules
# apply to the rewritten input. Codex and Pi drop updatedInput, so there the
# hook blocks with exit 2 instead.
#
# A Bash command without a URL, a network client, or a git subcommand that
# talks to a server, such as push or send-email, is left alone, so local
# commands such as `git log --author=<email>` keep working. In a command that
# is outbound, a local git step, one without a URL or a server subcommand such
# as push, is still left alone, so a chained
# `git commit --author=...` keeps its author. The match is literal: an address
# built at runtime or read from a variable gets through.
#
# Allowed: noreply addresses, the RFC 2606 example domains, `git@host:` SSH
# remotes, the login of the URL being requested such as `https://user@host/`,
# and the target of an ssh, scp, sftp, rsync or mosh command. A literal
# `curl -u <email>:<token>` is scrubbed, because it sends the address to
# whatever host the URL names; pass a basic-auth login through a variable.
# Bypass with SKIP_EMAIL_SCRUB=1.

[ "${SKIP_EMAIL_SCRUB:-}" = "1" ] && { cat >/dev/null; exit 0; }

# Every address the scrub matches holds @ or %40, which JSON may also spell
# \u0040. A payload with none of them has nothing to scrub, so it skips the
# Python start, about 20ms on each Bash call.
IFS= read -r -d '' INPUT
case "$INPUT" in
  *@*|*%40*|*'\u0040'*) ;;
  *) exit 0 ;;
esac

exec python3 -c '
import json, os, re, shlex, sys

REPLACEMENT = "redacted@example.invalid"
# A match starts after a %XX escape, so ?contact%3Djane%40corp.test keeps its key.
EMAIL = re.compile(
    r"(?:(?<=%[0-9A-F]{2})|(?<![A-Za-z0-9._%+-]))"
    r"[A-Za-z0-9._+-]+(?:@|%40)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}", re.I)
# ssh options that take a value, so the value is not mistaken for the destination.
SSH_VALUE_FLAGS = set("bcDEeFIiJLlmOopQRSWw")
GIT_NETWORK = {"push", "fetch", "pull", "clone", "ls-remote", "remote", "submodule",
               "send-email", "request-pull", "imap-send", "archive"}
# Commands whose URL argument is the request itself, so its userinfo is a login.
URL_CLIENTS = {"curl", "wget", "git", "http", "https", "xh"}
NETWORK = re.compile(
    r"https?://|(?:^|[^A-Za-z0-9_.-])"
    r"(?:curl|wget|http|https|xh|nc|ncat|socat|telnet|gh|Invoke-WebRequest|Invoke-RestMethod)"
    r"(?:[^A-Za-z0-9_.-]|$)", re.I)
ALLOWED_DOMAIN = re.compile(r"(?:^|\.)(?:example\.(?:com|org|net|invalid)|users\.noreply\.github\.com)$", re.I)
FIELDS = {"Bash": "command", "WebFetch": "url", "WebSearch": "query"}

try:
    payload = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
tool = payload.get("tool_name", "")
tool_input = payload.get("tool_input") or {}
field = FIELDS.get(tool)
text = tool_input.get(field) if field else None
if not isinstance(text, str) or not text:
    sys.exit(0)
found = []

def segment_bounds(s):
    """Spans of the commands in s, split at ; & | and newlines outside quotes
    and parentheses. A heredoc keeps the whole command as one span, because
    its body lines are data for the command, not commands of their own."""
    if "<<" in s:
        return [(0, len(s))]
    bounds, begin, quote, depth, i = [], 0, None, 0, 0
    while i < len(s):
        c = s[i]
        if c == "\\" and quote != "\x27":
            i += 2
            continue
        if quote:
            if c == quote:
                quote = None
        elif c in "\"\x27":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth = max(0, depth - 1)
        elif c in ";&|\n" and depth == 0:
            bounds.append((begin, i))
            begin = i + 1
        i += 1
    bounds.append((begin, len(s)))
    return bounds

SEGMENTS = segment_bounds(text) if tool == "Bash" else [(0, len(text))]
HEREDOC = tool == "Bash" and "<<" in text

def segment_at(start):
    for begin, finish in SEGMENTS:
        if begin <= start <= finish:
            return text[begin:finish], begin
    return text, 0

def words(s):
    try:
        tokens = shlex.split(s)
    except ValueError:
        return None
    while tokens and re.match(r"[A-Za-z_][A-Za-z0-9_]*=", tokens[0]):
        tokens.pop(0)
    return tokens

def git_step(segment):
    """The subcommand and its arguments when segment is a git command, else None."""
    tokens = words(segment)
    if not tokens or os.path.basename(tokens[0]) != "git":
        return None
    args, i = tokens[1:], 0
    while i < len(args):
        if args[i] in ("-c", "-C"):
            i += 2
        elif args[i].startswith("-"):
            i += 1
        else:
            return args[i], args[i + 1:]
    return "", []

def is_local_git(start):
    """True when the match sits in a git command that names no URL, such as a
    commit author or a config value. Rewriting it would leave a wrong commit,
    not a failed request. Subcommands that talk to a server, such as push, still
    count as outbound, because a -c http.userAgent value goes to that server, and
    so does a git config http.* value, which a later push sends. A heredoc span
    may hold several commands, so it never counts as local."""
    if HEREDOC:
        return False
    segment, _ = segment_at(start)
    step = git_step(segment)
    if step is None or "://" in segment:
        return False
    subcommand, rest = step
    if subcommand in GIT_NETWORK:
        return False
    return not (subcommand == "config" and any(t.lower().startswith("http.") for t in rest))

def is_userinfo(start, end):
    """True when the match is the login of the URL being requested: the WebFetch
    URL itself, or a Bash word that starts with a scheme and is not an option
    value. A URL inside a header, a User-Agent or a search query is data sent to
    another host, so its address stays scrubbed. Parsers split the authority at
    its last @, so a later @ also means the match goes to another host."""
    scheme = text.rfind("://", 0, start)
    if tool == "WebSearch" or scheme < 0 or re.search(r"[/?#\s]", text[scheme + 3:start]):
        return False
    authority_rest = re.match(r"[^/?#\s\"\x27]*", text[end:]).group(0)
    if "@" in authority_rest:
        return False
    if tool == "WebFetch":
        return re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*", text[:scheme]) is not None
    segment, begin = segment_at(start)
    prefix = segment[:start - begin]
    if "$(" in prefix or "`" in prefix:
        return False
    for closing in ("", "\"", "\x27"):
        tokens = words(prefix + closing)
        if tokens is not None:
            break
    else:
        return False
    if len(tokens) < 2 or os.path.basename(tokens[0]) not in URL_CLIENTS \
            or not re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*://[^/?#\s]*", tokens[-1]):
        return False
    return not tokens[-2].startswith("-")

def is_login_target(start, end):
    """True when the match is the destination of an ssh-family command: the
    first non-option argument of ssh, mosh or sftp, or a user@host: operand of
    scp or rsync. An address inside the remote command is not a destination."""
    if start and not text[start - 1].isspace():
        return False
    whole, begin = segment_at(start)
    segment = whole[:start - begin]
    try:
        tokens = shlex.split(segment)
    except ValueError:
        return False
    if not tokens:
        return False
    command = os.path.basename(tokens[0])
    if command in ("scp", "rsync"):
        return text[end:end + 1] == ":"
    if command not in ("ssh", "mosh", "sftp"):
        return False
    args = iter(tokens[1:])
    for token in args:
        if token.startswith("-") and len(token) > 1:
            if len(token) == 2 and token[1] in SSH_VALUE_FLAGS:
                next(args, None)
            continue
        return False
    return end == len(text) or text[end] in " \t\n:"

def scrub(match):
    address = match.group(0)
    encoded = "@" not in address
    local, domain = re.split(r"@|%40", address, maxsplit=1, flags=re.I)
    start, end = match.start(), match.end()
    if local.lower() == "git" and text[end:end + 1] == ":":
        return address
    # A plain user@host login stays; an encoded one is scrubbed so it cannot pose as a login.
    if not encoded and is_userinfo(start, end):
        return address
    if not encoded and tool == "Bash" and (is_login_target(start, end) or is_local_git(start)):
        return address
    if re.fullmatch(r"no-?reply", local, re.I) or ALLOWED_DOMAIN.search(domain):
        return address
    found.append(address)
    return REPLACEMENT.replace("@", "%40") if encoded else REPLACEMENT

def is_outbound():
    if NETWORK.search(text):
        return True
    return any((git_step(text[b:f]) or ("",))[0] in GIT_NETWORK for b, f in SEGMENTS)

if tool == "Bash" and not is_outbound():
    sys.exit(0)

scrubbed = EMAIL.sub(scrub, text)
if not found:
    sys.exit(0)

addresses = ", ".join(sorted(set(found)))
if os.environ.get("AGENT_HOOK_HOST"):
    sys.stderr.write(
        "[pre-outbound-email-scrub] Refusing to send an email address off the machine: " + addresses + "\n"
        "Remove it from the " + tool + " call. A site asking for a contact email does not need yours.\n"
        "(Bypass: SKIP_EMAIL_SCRUB=1)\n")
    sys.exit(2)

updated = dict(tool_input)
updated[field] = scrubbed
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": updated,
    "additionalContext": "[pre-outbound-email-scrub] Replaced " + str(len(found))
        + " email address(es) with " + REPLACEMENT + " before this " + tool
        + " call left the machine. Do not put a real address back.",
}}))
' <<< "$INPUT"
