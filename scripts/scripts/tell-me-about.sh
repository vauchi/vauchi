#!/usr/bin/env bash
# tell-me-about.sh - Quick codebase exploration using local LLM
# Uses ollama with a tiny model to generate search terms and summarize findings

set -e

# Configuration
MODEL="${TELL_ME_MODEL:-qwen2:0.5b}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
MAX_RESULTS=20
MAX_CONTENT_LINES=100

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

usage() {
    echo -e "${BLUE}tell-me-about${NC} - Quick codebase exploration"
    echo ""
    echo "Usage: $0 <topic>"
    echo ""
    echo "Examples:"
    echo "  $0 'iOS tests'"
    echo "  $0 'recovery feature'"
    echo "  $0 'crypto implementation'"
    echo "  $0 'relay server'"
    echo ""
    echo "Environment:"
    echo "  TELL_ME_MODEL  Ollama model (default: qwen2:0.5b)"
    echo "  PROJECT_ROOT   Project root (default: auto-detect)"
}

if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
    exit 0
fi

TOPIC="$*"

# Check ollama
if ! command -v ollama &>/dev/null; then
    echo -e "${YELLOW}Error: ollama not found. Install from https://ollama.ai${NC}"
    exit 1
fi

echo -e "${BLUE}Searching for:${NC} $TOPIC"
echo -e "${DIM}Using model: $MODEL${NC}"
echo ""

# Step 1: Generate search keywords using LLM
echo -e "${CYAN}Generating search terms...${NC}"

KEYWORDS_PROMPT="You are a code search assistant. Given a topic, output 5-8 search keywords/patterns that would help find relevant files and code in a software project. Output ONLY the keywords, one per line, no explanations.

Topic: $TOPIC

Keywords:"

KEYWORDS=$(ollama run "$MODEL" "$KEYWORDS_PROMPT" 2>/dev/null | grep -v '^$' | head -8)

# Always include original topic words
TOPIC_WORDS=$(echo "$TOPIC" | tr ' ' '\n' | grep -v '^$')
KEYWORDS="$TOPIC_WORDS"$'\n'"$KEYWORDS"

echo -e "${DIM}Keywords: $(echo $KEYWORDS | tr '\n' ', ')${NC}"
echo ""

# Step 2: Search for files
echo -e "${CYAN}Searching files...${NC}"

FOUND_FILES=""
FOUND_CONTENT=""

cd "$PROJECT_ROOT"

# Search for matching files by name
while IFS= read -r keyword; do
    [[ -z "$keyword" ]] && continue
    # Clean keyword (remove quotes, special chars)
    clean_kw=$(echo "$keyword" | tr -d '"' | tr -d "'" | tr -cs '[:alnum:]_-' ' ' | xargs)
    [[ -z "$clean_kw" ]] && continue

    # File search
    files=$(find . -type f \( -name "*.rs" -o -name "*.swift" -o -name "*.kt" -o -name "*.md" -o -name "*.sh" -o -name "*.feature" -o -name "*.toml" -o -name "*.json" \) \
        -not -path "*/target/*" -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/DerivedData/*" \
        2>/dev/null | grep -i "$clean_kw" | head -5) || true

    if [[ -n "$files" ]]; then
        FOUND_FILES="$FOUND_FILES"$'\n'"$files"
    fi
done <<< "$KEYWORDS"

# Search for content matches
while IFS= read -r keyword; do
    [[ -z "$keyword" ]] && continue
    clean_kw=$(echo "$keyword" | tr -d '"' | tr -d "'" | tr -cs '[:alnum:]_-' ' ' | xargs)
    [[ -z "$clean_kw" ]] && continue

    # Content search with context
    content=$(grep -rn --include="*.rs" --include="*.swift" --include="*.kt" --include="*.md" --include="*.sh" --include="*.feature" \
        -i "$clean_kw" . \
        --exclude-dir=target --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=DerivedData \
        2>/dev/null | head -10) || true

    if [[ -n "$content" ]]; then
        FOUND_CONTENT="$FOUND_CONTENT"$'\n'"$content"
    fi
done <<< "$KEYWORDS"

# Deduplicate and limit results
FOUND_FILES=$(echo "$FOUND_FILES" | sort -u | grep -v '^$' | head -$MAX_RESULTS)
FOUND_CONTENT=$(echo "$FOUND_CONTENT" | sort -u | grep -v '^$' | head -$MAX_CONTENT_LINES)

# Step 3: Display results
echo ""
echo -e "${GREEN}=== Relevant Files ===${NC}"
if [[ -n "$FOUND_FILES" ]]; then
    echo "$FOUND_FILES" | while read -r f; do
        [[ -n "$f" ]] && echo -e "  ${CYAN}$f${NC}"
    done
else
    echo -e "  ${DIM}No files found${NC}"
fi

echo ""
echo -e "${GREEN}=== Key Locations ===${NC}"

# Extract unique file paths from content matches
if [[ -n "$FOUND_CONTENT" ]]; then
    echo "$FOUND_CONTENT" | cut -d: -f1 | sort -u | head -10 | while read -r f; do
        [[ -n "$f" ]] && echo -e "  ${CYAN}$f${NC}"
    done
fi

echo ""
echo -e "${GREEN}=== Sample Matches ===${NC}"
if [[ -n "$FOUND_CONTENT" ]]; then
    echo "$FOUND_CONTENT" | head -15 | while read -r line; do
        # Truncate long lines
        if [[ ${#line} -gt 120 ]]; then
            echo -e "  ${DIM}${line:0:120}...${NC}"
        else
            echo -e "  ${DIM}$line${NC}"
        fi
    done
else
    echo -e "  ${DIM}No content matches found${NC}"
fi

# Step 4: Generate summary using LLM
echo ""
echo -e "${CYAN}Generating summary...${NC}"

# Prepare context for summary (truncate to avoid token limits)
CONTEXT="Files found:
$FOUND_FILES

Content matches (sample):
$(echo "$FOUND_CONTENT" | head -30)"

SUMMARY_PROMPT="Based on these search results from a codebase, provide a brief summary (3-5 sentences) about '$TOPIC'. Mention key files, their purposes, and any relevant scripts or commands. Be concise.

$CONTEXT

Summary:"

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
ollama run "$MODEL" "$SUMMARY_PROMPT" 2>/dev/null | head -20

echo ""
echo -e "${DIM}---${NC}"
echo -e "${DIM}Tip: For more detail, read the files directly or run: just check${NC}"
