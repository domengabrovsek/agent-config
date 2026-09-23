#!/bin/bash
# Host-neutral hook dispatcher: runs the hooks registered in settings.json for
# one event, so Codex and Pi enforce the same gates Claude Code runs natively.
#
# Usage: dispatch.sh <Event>, with a Claude-shaped payload on stdin.
#
# Other hosts cannot evaluate the registry's `if` rules and run matching hooks
# concurrently, so each host registers this one entry per event and the
# dispatcher filters and runs the registry's hooks in order. Tool names are
# normalized to Claude's (bash/exec_command -> Bash, edit -> Edit), and a Codex
# apply_patch becomes one Edit call per patched file, because the edit hooks
# read tool_input.file_path.
#
# Registry commands fall back to $HOME/.claude/hooks, which a machine set up
# only for Codex or Pi lacks. The dispatcher rewrites that prefix to its own
# repo's hooks directory, which is what ~/.claude/hooks links to anyway.
#
# Exit 2 with the first blocking hook's stderr; every other failure is ignored,
# as Claude Code does. additionalContext from all hooks is merged into one
# JSON object on stdout.
#
# HOOK_REGISTRY overrides the registry path (used by tests).

DISPATCH_SELF="${BASH_SOURCE[0]}"

# The Python program is passed with -c so stdin stays the hook payload.
read -r -d '' DISPATCH_PY <<'PY'
import json, os, re, signal, subprocess, sys

self_path, args = sys.argv[1], sys.argv[2:]
repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(self_path))))
registry_path = os.environ.get("HOOK_REGISTRY") or os.path.join(repo, "settings.json")

try:
    payload = json.loads(sys.stdin.read() or "{}")
except ValueError:
    sys.exit(0)
if not isinstance(payload, dict):
    sys.exit(0)

event = args[0] if args else payload.get("hook_event_name", "")
try:
    with open(registry_path) as f:
        groups = (json.load(f).get("hooks") or {}).get(event) or []
except (OSError, ValueError, AttributeError) as err:
    sys.stderr.write("[dispatch] cannot read hook registry %s: %s\n" % (registry_path, err))
    sys.exit(0)
if not groups:
    sys.exit(0)

cwd = payload.get("cwd") or os.getcwd()
TOOL_ALIASES = {
    "bash": "Bash", "shell": "Bash", "shell_command": "Bash", "exec_command": "Bash",
    "local_shell": "Bash", "unified_exec": "Bash", "edit": "Edit", "write": "Write",
}


def absolute(path):
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))


def command_text(value):
    if isinstance(value, list):
        # A shell tool may pass argv such as ["bash", "-lc", "<script>"].
        if len(value) >= 3 and value[-2] in ("-c", "-lc"):
            return str(value[-1])
        return " ".join(str(v) for v in value)
    return value if isinstance(value, str) else ""


def patch_paths(patch):
    paths = []
    for line in patch.splitlines():
        m = re.match(r"^\*\*\* (?:Add File|Update File|Move to): (.+?)\s*$", line)
        if m and absolute(m.group(1)) not in paths:
            paths.append(absolute(m.group(1)))
    return paths


def tool_calls(data):
    """Yield (tool_name, payload) pairs after normalizing the host's tool call."""
    name = data.get("tool_name")
    if not name:
        yield "", data
        return
    tool_input = dict(data.get("tool_input") or {})
    if name == "apply_patch":
        patch = command_text(tool_input.get("command")) or tool_input.get("input") or tool_input.get("patch") or ""
        for path in patch_paths(patch):
            yield "Edit", dict(data, tool_name="Edit", tool_input={"file_path": path})
        return
    name = TOOL_ALIASES.get(name.lower(), name)
    if name == "Bash" and "command" in tool_input:
        tool_input["command"] = command_text(tool_input["command"])
    if name in ("Edit", "Write"):
        path = tool_input.get("file_path") or tool_input.get("path")
        if path:
            tool_input["file_path"] = absolute(path)
    yield name, dict(data, tool_name=name, tool_input=tool_input)


def glob_match(pattern, text):
    text = text.strip()
    regex = ".*".join(re.escape(part) for part in pattern.split("*"))
    if re.fullmatch(regex, text, re.S):
        return True
    # Claude treats `git push *` as also matching a bare `git push`.
    return pattern.endswith(" *") and text == pattern[:-2]


def if_matches(rule, name, tool_input):
    m = re.match(r"^(\w+)\((.*)\)$", rule or "", re.S)
    if not m or m.group(1) != name:
        return False
    if name == "Bash":
        command = tool_input.get("command") or ""
        segments = [command] + re.split(r"&&|\|\||;|\||\n", command)
        return any(glob_match(m.group(2), s) for s in segments if s.strip())
    return glob_match(m.group(2), tool_input.get("file_path") or "")


def matcher_matches(matcher, target):
    if matcher in (None, "", "*"):
        return True
    try:
        return re.fullmatch(matcher, target or "") is not None
    except re.error:
        return matcher == target


MATCH_FIELDS = {"SessionStart": "source", "SessionEnd": "reason", "Notification": "notification_type"}

try:
    top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True).stdout.strip()
except OSError:
    top = ""
# Hooks that differ by host read AGENT_HOOK_HOST. The Pi bridge sets "pi";
# Codex is the only host that calls the dispatcher directly.
env = dict(os.environ, CLAUDE_PROJECT_DIR=top or cwd, AGENT_CONFIG_HOOKS=os.path.join(repo, "hooks"),
           AGENT_HOOK_HOST=os.environ.get("AGENT_HOOK_HOST", "codex"))
run_dir = cwd if os.path.isdir(cwd) else None
contexts = []


def run_hook(hook, call):
    command = hook.get("command") or ""
    for prefix in ("$HOME/.claude/hooks/", "~/.claude/hooks/"):
        command = command.replace(prefix, "$AGENT_CONFIG_HOOKS/")
    proc = subprocess.Popen(["bash", "-c", command], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, cwd=run_dir, start_new_session=True)
    try:
        out, err = proc.communicate(json.dumps(call).encode(), timeout=hook.get("timeout") or 60)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return
    if proc.returncode == 2:
        sys.stderr.write(err.decode(errors="replace"))
        sys.exit(2)
    if proc.returncode != 0:
        return
    text = out.decode(errors="replace").strip()
    if not text:
        return
    try:
        parsed = json.loads(text)
    except ValueError:
        parsed = None
    if isinstance(parsed, dict):
        specific = parsed.get("hookSpecificOutput")
        extra = specific.get("additionalContext") if isinstance(specific, dict) else None
        if extra:
            contexts.append(extra)
    elif event in ("SessionStart", "UserPromptSubmit"):
        # Claude adds plain stdout from these events to the context.
        contexts.append(text)


for name, call in tool_calls(payload):
    target = name if name else payload.get(MATCH_FIELDS.get(event, ""), "")
    tool_input = call.get("tool_input") or {}
    for group in groups:
        if not matcher_matches(group.get("matcher"), target):
            continue
        for hook in group.get("hooks") or []:
            if hook.get("type", "command") != "command":
                continue
            if hook.get("if") and not if_matches(hook["if"], name, tool_input):
                continue
            run_hook(hook, call)

if contexts:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": "\n\n".join(contexts)}}))
PY

exec python3 -c "$DISPATCH_PY" "$DISPATCH_SELF" "$@"
