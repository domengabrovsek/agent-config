#!/bin/bash
# Prose gate backing the "Write plain" policy in AGENTS.md.
#
# One word list, three surfaces, dispatched by the first argument:
#   file    PostToolUse on Write|Edit  - markdown files only
#   commit  PreToolUse on git commit   - the whole commit message
#   pr      PreToolUse on gh pr create|edit - the body text it sends
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

# shellcheck source=lib/pr-body.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/pr-body.sh"
# shellcheck source=lib/commit-msg.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/commit-msg.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"

# These carry the lists themselves, so checking them flags their own text.
lists_itself() {
  case "/$1" in
    */CLAUDE.md|*/rules/communication.md|*/skills/write-plain/SKILL.md|*/.claude/state/*) return 0 ;;
  esac
  return 1
}

MODE="${1:-file}"

# corpus mode takes a path and reads no stdin; every other mode reads hook JSON.
# Read it before the bypass check so the writer never hits a closed pipe.
INPUT=""
if [ "$MODE" != "corpus" ]; then
  INPUT=$(cat)
fi

case "$MODE" in
  commit|pr) first_run_for_call "$INPUT" "prose-gate-$MODE" || exit 0 ;;
esac

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
    lists_itself "$FILE" && exit 0

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
    commit_reuses_message "$COMMAND" && exit 0

    LABEL="commit message"
    TEXT=$(extract_commit_msg "$COMMAND")
    ;;

  pr)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    case "$COMMAND" in
      *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
      *"gh pr edit --help"*|*"gh pr edit -h"*) exit 0 ;;
      *"gh pr create"*|*"gh pr edit"*) ;;
      *) exit 0 ;;
    esac

    LABEL="PR body"
    TEXT=$(extract_pr_body "$COMMAND")
    ;;

  corpus)
    FILE="${2:-}"
    [ -z "$FILE" ] && { echo "[prose-gate] corpus mode needs a file path" >&2; exit 1; }
    [ ! -f "$FILE" ] && { echo "[prose-gate] no such file: $FILE" >&2; exit 1; }

    lists_itself "$FILE" && exit 0
    # Accepted ADRs are immutable, so the corpus pass cannot ask for a
    # rewrite. New ADRs are still gated by file mode as they are written.
    case "$FILE" in
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
printf '%s' "$TEXT" | python3 -c '
import re, sys

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
    (r"since\s+(?:the|it|it\x27s|its|we|you|this|that|they|there|an?)",
     "write \"because\" for cause; \"since\" marks time"),
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

sys.stdout = sys.stderr
label = sys.argv[1]

def report(items):
    for n, word, fix in sorted(items):
        print(f"  line {n}: {word!r} -> {fix}")

if advisories:
    print(f"[prose-gate] {label} (advisory)")
    report(advisories)

if blocks:
    print(f"[prose-gate] {label}")
    print("AGENTS.md (Write plain): plain word, no filler, no chatbot phrasing.")
    report(blocks)
    print("(Bypass: SKIP_PROSE_GATE=1)")
    sys.exit(2)
' "$LABEL"
[ $? -eq 2 ] && exit 2
exit 0
