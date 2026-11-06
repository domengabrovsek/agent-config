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
# A Bash command without a URL or network client is left alone, so local
# commands such as `git log --author=<email>` keep working. The match is
# literal: an address built at runtime or read from a variable gets through.
#
# Allowed: noreply addresses, the RFC 2606 example domains, `git@host:` SSH
# remotes, URL userinfo such as `https://user@host/`, and the target of an
# ssh, scp, sftp, rsync or mosh command.
# Bypass with SKIP_EMAIL_SCRUB=1.

[ "${SKIP_EMAIL_SCRUB:-}" = "1" ] && { cat >/dev/null; exit 0; }

exec python3 -c '
import json, os, re, shlex, sys

REPLACEMENT = "redacted@example.invalid"
# A match starts after a %XX escape, so ?contact%3Djane%40corp.test keeps its key.
EMAIL = re.compile(
    r"(?:(?<=%[0-9A-F]{2})|(?<![A-Za-z0-9._%+-]))"
    r"[A-Za-z0-9._+-]+(?:@|%40)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}", re.I)
# ssh options that take a value, so the value is not mistaken for the destination.
SSH_VALUE_FLAGS = set("bcDEeFIiJLlmOopQRSWw")
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
if tool == "Bash" and not NETWORK.search(text):
    sys.exit(0)

found = []

def is_login_target(start, end):
    """True when the match is the destination of an ssh-family command: the
    first non-option argument of ssh, mosh or sftp, or a user@host: operand of
    scp or rsync. An address inside the remote command is not a destination."""
    if start and not text[start - 1].isspace():
        return False
    segment = re.split(r"[;&|\n]", text[:start])[-1]
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
    # A plain user@host in URL userinfo or as an ssh-family target is a login; an encoded one stays scrubbed.
    scheme = text.rfind("://", 0, start)
    # Parsers split the authority at its last @, so a later @ sends this match to another host.
    authority_rest = re.match(r"[^/?#\s\"]*", text[end:]).group(0)
    if not encoded and scheme >= 0 and not re.search(r"[/?#\s]", text[scheme + 3:start]) \
            and "@" not in authority_rest:
        return address
    if not encoded and tool == "Bash" and is_login_target(start, end):
        return address
    if re.fullmatch(r"no-?reply", local, re.I) or ALLOWED_DOMAIN.search(domain):
        return address
    found.append(address)
    return REPLACEMENT.replace("@", "%40") if encoded else REPLACEMENT

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
'
