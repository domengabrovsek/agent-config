#!/bin/bash
# Prose gate backing the "Write plain" policy in CLAUDE.md.
#
# One word list, three surfaces, dispatched by the first argument:
#   file    PostToolUse on Write|Edit  - markdown files only
#   commit  PreToolUse on git commit   - the whole commit message
#   pr      PreToolUse on gh pr create - the --body / --body-file text
#   corpus  CI / test only              - a whole markdown file by path
#
# Two tiers. BLOCK words have no defensible use in this repo and exit 2.
# ADVISORY words have a real but rare use, so they print and pass.
#
# Sentence shape follows ASD-STE100 and rides the advisory tier. A sentence
# over the cap and a causal "since" are the two STE rules a line-oriented
# check can judge. Noun clusters need part-of-speech tagging, and paragraph
# length needs boundaries a unified=0 diff throws away.
#
# Deliberately unchecked: surface, features, vector, harness. All four are
# terms of art here, so a check would fire on correct usage. Sentence-case
# headings and mid-sentence colons are unchecked for the same reason: the
# doc-title convention and the "term: definition" rule format rely on both.
#
# Bypass: SKIP_PROSE_GATE=1.
#
# shellcheck disable=SC1112  # the curly quotes below are the patterns
# this gate detects, inside the embedded python; they are not typos.

MODE="${1:-file}"

# corpus mode takes a path and reads no stdin; every other mode reads hook JSON.
# Read it before the bypass check so the writer never hits a closed pipe.
INPUT=""
if [ "$MODE" != "corpus" ]; then
  INPUT=$(cat)
fi

[ "$SKIP_PROSE_GATE" = "1" ] && exit 0

# ---------------------------------------------------------------------------
# Extract the text to check, per mode.
# ---------------------------------------------------------------------------
LABEL=""
TEXT=""

case "$MODE" in
  file)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -z "$FILE" ] && exit 0
    [ ! -f "$FILE" ] && exit 0

    case "$FILE" in
      *.md|*.markdown) ;;
      *) exit 0 ;;
    esac

    # These carry the lists themselves, so checking them flags their own text.
    case "$FILE" in
      */CLAUDE.md|*/rules/communication.md) exit 0 ;;
      */skills/write-plain/SKILL.md) exit 0 ;;
      */.claude/state/*) exit 0 ;;
    esac

    LABEL="$FILE"
    FILE_DIR=$(dirname "$FILE")
    if git -C "$FILE_DIR" rev-parse --git-dir >/dev/null 2>&1 \
      && git -C "$FILE_DIR" ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
      TEXT=$(git -C "$FILE_DIR" diff --unified=0 HEAD -- "$FILE" 2>/dev/null | grep -E '^\+[^+]' | sed 's/^\+//')
    else
      TEXT=$(cat "$FILE")
    fi
    ;;

  commit)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    case "$COMMAND" in
      *"git commit --help"*|*"git commit -h"*) exit 0 ;;
      *"git commit"*) ;;
      *) exit 0 ;;
    esac

    # Auto-generated or reused messages are not ours to police.
    if echo "$COMMAND" | grep -qE -- '(--amend|--fixup=|--squash=|--no-edit|-C[[:space:]]+|--reuse-message=)'; then
      exit 0
    fi

    LABEL="commit message"
    TEXT=$(printf '%s' "$COMMAND" | python3 -c '
import sys, re

cmd = sys.stdin.read()

# Only a heredoc opened after `git commit` can carry its message. A command
# chain may open others first, such as a PR body written to a file, and
# reading those attributes unrelated prose to this change.
anchor = cmd.find("git commit")
scope = cmd[anchor:] if anchor != -1 else cmd

# A heredoc carries the structured multi-line message when one is used.
m = re.search(r"<<-?[\x27\"]?(\w+)[\x27\"]?", scope)
if m:
    delim = m.group(1)
    after = scope[m.end():]
    nl = after.find("\n")
    if nl != -1:
        out = []
        for line in after[nl + 1:].split("\n"):
            if line.strip() == delim:
                break
            out.append(line)
        print("\n".join(out))
        sys.exit(0)

# Otherwise collect every -m / --message value. The backreference keeps a
# quote of the other kind inside the message from ending the match early.
vals = [m.group(2) for m in
        re.finditer(r"(?:-m|--message)[=\s]+([\x27\"])(.*?)\1", scope, re.S)]
if vals:
    print("\n".join(vals))
' 2>/dev/null)
    ;;

  pr)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    case "$COMMAND" in
      *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
      *"gh pr create"*) ;;
      *) exit 0 ;;
    esac

    LABEL="PR body"
    BODY_FILE=$(printf '%s' "$COMMAND" | python3 -c '
import sys, re
cmd = sys.stdin.read()
m = re.search(r"--body-file[=\s]+[\x27\"]?([^\x27\"\s]+)", cmd)
print(m.group(1) if m else "")
' 2>/dev/null)

    if [ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ]; then
      TEXT=$(cat "$BODY_FILE")
    else
      TEXT=$(printf '%s' "$COMMAND" | python3 -c '
import sys, re

cmd = sys.stdin.read()

m = re.search(r"--body[=\s]+<<-?[\x27\"]?(\w+)[\x27\"]?", cmd)
if m:
    delim = m.group(1)
    after = cmd[m.end():]
    nl = after.find("\n")
    if nl != -1:
        out = []
        for line in after[nl + 1:].split("\n"):
            if line.strip() == delim:
                break
            out.append(line)
        print("\n".join(out))
        sys.exit(0)

vals = [m.group(2) for m in
        re.finditer(r"(?:-b|--body)[=\s]+([\x27\"])(.*?)\1", cmd, re.S)]
if vals:
    print("\n".join(vals))
' 2>/dev/null)
    fi
    ;;

  corpus)
    FILE="${2:-}"
    [ -z "$FILE" ] && { echo "[prose-gate] corpus mode needs a file path" >&2; exit 1; }
    [ ! -f "$FILE" ] && { echo "[prose-gate] no such file: $FILE" >&2; exit 1; }

    case "$FILE" in
      */CLAUDE.md|CLAUDE.md) exit 0 ;;
      */rules/communication.md|rules/communication.md) exit 0 ;;
      */skills/write-plain/SKILL.md|skills/write-plain/SKILL.md) exit 0 ;;
      */.claude/state/*) exit 0 ;;
      # Accepted ADRs are immutable, so the corpus pass cannot ask for a
      # rewrite. New ADRs are still gated by file mode as they are written.
      */docs/adr/*|docs/adr/*) exit 0 ;;
    esac

    LABEL="$FILE"
    TEXT=$(cat "$FILE")
    ;;

  *)
    echo "[prose-gate] Unknown mode: $MODE (expected file, commit, pr or corpus)" >&2
    exit 1
    ;;
esac

[ -z "$TEXT" ] && exit 0

# ---------------------------------------------------------------------------
# Check. Patterns live in one place; the tier decides block versus advise.
# ---------------------------------------------------------------------------
RESULT=$(printf '%s' "$TEXT" | LABEL="$LABEL" python3 -c '
import os, re, sys

text = sys.stdin.read()

BLOCK = [
    # Fancy words with a plain equivalent.
    (r"utili[sz]e[sd]?", "use"),
    (r"homogeni[sz]e[sd]?", "make the same"),
    (r"crystalli[sz]e[sd]?", "settle"),
    (r"synthesi[sz]e[sd]?", "combine"),
    (r"orthogonal", "unrelated"),
    (r"holistic", "whole"),
    (r"paradigm", "model"),
    (r"synerg\w*", "name the actual gain"),
    (r"salient", "main"),
    (r"delv(?:e|es|ed|ing)", "look at"),
    (r"seamless(?:ly)?", "name what does not break"),
    (r"crucial", "needed, or say why"),
    (r"enduring", "lasting, or a duration"),
    (r"fostering", "name what it causes"),
    (r"garner(?:s|ed|ing)?", "get"),
    (r"interplay", "how they interact"),
    (r"intricate", "detailed"),
    (r"pivotal", "name the effect"),
    (r"showcas(?:e|es|ed|ing)", "show"),
    (r"tapestry", "name the thing"),
    (r"testament", "state what happened"),
    (r"vibrant", "a neutral description"),
    (r"facilitat(?:e|es|ed|ing)", "help"),
    (r"numerous", "many, or the number"),
    (r"in the event that", "if"),
    (r"due to the fact that", "because"),
    # Fancy ways to say "is" or "has".
    (r"boasts?", "is, or has"),
    (r"serves as", "is"),
    (r"stands as", "is"),
    # Abstract metaphor nouns with a concrete equivalent.
    (r"substrate", "base"),
    (r"locus", "place"),
    (r"vantage", "view"),
    (r"nexus", "link"),
    (r"bedrock", "base"),
    (r"modality", "mode"),
    (r"gold-plating", "more than the job needs"),
    (r"flywheel", "name the mechanism"),
    (r"north star", "the goal"),
    (r"endgame", "the last phase"),
]

BLOCK_PHRASE = [
    # Scaffolding that reads as filler wherever it appears.
    (r"it[’\x27]?s worth noting", "delete it"),
    (r"it is worth noting", "delete it"),
    (r"it[’\x27]?s important to", "delete it"),
    (r"it is important to", "delete it"),
    (r"we[’\x27]?ll want to", "say who does what"),
    (r"we will want to", "say who does what"),
    (r"i should mention", "just mention it"),
    (r"to make sure .{0,40}? let[’\x27]?s", "say the action"),
    # Chatbot and sycophantic artifacts.
    (r"i hope this helps", "delete it"),
    (r"let me know if", "delete it"),
    (r"of course!", "delete it"),
    (r"certainly!", "delete it"),
    (r"great question", "answer it"),
    (r"you[’\x27]?re absolutely right", "answer directly"),
    (r"found the smoking gun", "state the finding"),
    # Stacked hedging.
    (r"(?:could|might|may) potentially", "pick one"),
    (r"potentially possibly", "pick one"),
    (r"it (?:could|might) be argued", "argue it or drop it"),
]

ADVISE = [
    (r"robust", "sturdy"),
    (r"comprehensive", "full"),
    (r"leverag(?:e|es|ed|ing)", "use"),
    (r"in order to", "to"),
    (r"landscape", "the concrete word"),
    (r"additionally", "and, or start the sentence"),
    (r"enhanc(?:e|es|ed|ement|ements|ing)", "improve, or the number"),
    (r"wedge", "add"),
    (r"ratchet", "the real mechanism"),
    (r"evacuate", "move out"),
    (r"scaffolding", "the real structure"),
    (r"primitive", "the real name"),
]

CURLY = "‘’“”"
EMOJI = re.compile(
    "[\U0001F300-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F]"
)

lines = text.split("\n")
blocks, advisories = [], []

def scan(rules, sink, word_boundary=True):
    for pat, fix in rules:
        rx = (r"\b" + pat + r"\b") if word_boundary else pat
        for n, line in enumerate(lines, 1):
            m = re.search(rx, line, re.IGNORECASE)
            if m:
                sink.append((n, m.group(0), fix))
                break

scan(BLOCK, blocks)
scan(BLOCK_PHRASE, blocks, word_boundary=False)
scan(ADVISE, advisories)

# ASD-STE100 sentence cap. 20 words for a step, 25 for description; the check
# uses the looser number because a line carries no step-versus-description
# marker. Headings, tables, blockquotes and fenced code carry no sentences.
SENTENCE_CAP = 25
STRUCTURE = re.compile(r"^\s*(#|\||>)")
SENTENCE_END = re.compile(r"[.!?]+(?:\s+|$)")

def sentences(line):
    line = re.sub(r"`[^`]*`", "code", line)
    line = re.sub(r"\[[^\]]*\]\([^)]*\)", "link", line)
    line = re.sub(r"https?://\S+", "url", line)
    return [s for s in SENTENCE_END.split(line) if re.search(r"[A-Za-z]", s)]

long_hits = []
fenced = False
for n, line in enumerate(lines, 1):
    if line.lstrip().startswith("```"):
        fenced = not fenced
        continue
    if fenced or STRUCTURE.match(line):
        continue
    for sentence in sentences(line):
        count = len(sentence.split())
        if count > SENTENCE_CAP:
            long_hits.append((n, f"{count}-word sentence",
                              "split it; the cap is 20 for a step, 25 for description"))

# One report per sentence would take ten rounds on a long file, so show a
# batch. Five is enough to see the pattern without burying the word list.
advisories.extend(long_hits[:5])

CAUSAL_SINCE = re.compile(
    r"\bsince\s+(?:the|it|it\x27s|its|we|you|this|that|they|there|an?)\b",
    re.IGNORECASE)
for n, line in enumerate(lines, 1):
    m = CAUSAL_SINCE.search(line)
    if m:
        advisories.append((n, m.group(0),
                           "write \"because\" for cause; \"since\" marks time"))
        break

for n, line in enumerate(lines, 1):
    hit = [c for c in CURLY if c in line]
    if hit:
        blocks.append((n, "".join(hit), "straight quotes"))
        break

for n, line in enumerate(lines, 1):
    if line.lstrip().startswith("#"):
        m = EMOJI.search(line)
        if m:
            blocks.append((n, m.group(0), "drop the emoji"))
            break

label = os.environ.get("LABEL", "text")

if advisories:
    print("ADVISE", file=sys.stderr)
    for n, word, fix in sorted(advisories):
        print(f"  line {n}: {word!r} -> {fix}", file=sys.stderr)

if blocks:
    print("BLOCK", file=sys.stderr)
    for n, word, fix in sorted(blocks):
        print(f"  line {n}: {word!r} -> {fix}", file=sys.stderr)
    sys.exit(2)

sys.exit(0)
' 2>&1)
STATUS=$?

if echo "$RESULT" | grep -q '^ADVISE$'; then
  echo "[prose-gate] $LABEL (advisory)" >&2
  echo "$RESULT" | sed -n '/^ADVISE$/,/^BLOCK$/p' | grep -v '^ADVISE$' | grep -v '^BLOCK$' >&2
fi

if [ "$STATUS" -eq 2 ]; then
  echo "[prose-gate] $LABEL" >&2
  echo "CLAUDE.md (Write plain): plain word, no filler, no chatbot phrasing." >&2
  echo "$RESULT" | sed -n '/^BLOCK$/,$p' | grep -v '^BLOCK$' >&2
  echo "(Bypass: SKIP_PROSE_GATE=1)" >&2
  exit 2
fi

exit 0
