#!/bin/bash

################################################################################
# Fetch All Game URLs Locally
#
# This script fetches game URLs from the API (which requires IP whitelist)
# and saves them to a JSON file for use in remote testing
################################################################################

set -euo pipefail

# Source the game test common library
GAME_TEST_DIR="/Users/lonelyhsu/gemini/toolkits/game_login/game-test"
source "$GAME_TEST_DIR/lib/common.sh"

# Output file
OUTPUT_FILE="game-urls.json"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Fetching Game URLs from API                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "Total games available: ${#ALL_GAMES[@]}"
echo "Language: zh-CN"
echo ""

# Create JSON array
echo "{" > "$OUTPUT_FILE"
echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$OUTPUT_FILE"
echo "  \"total_games\": ${#ALL_GAMES[@]}," >> "$OUTPUT_FILE"
echo "  \"games\": {" >> "$OUTPUT_FILE"

SUCCESS_COUNT=0
FAIL_COUNT=0
GAME_COUNT=${#ALL_GAMES[@]}

for ((i=0; i<${#ALL_GAMES[@]}; i++)); do
    game=${ALL_GAMES[$i]}
    echo -e "${CYAN}[$((i+1))/${GAME_COUNT}] Fetching URL for ${game}...${NC}"

    # Try to get game URL
    set +e
    url=$(get_game_url "$game" "zh-CN" 2>&1)
    result=$?
    set -e

    if [ $result -eq 0 ] && [ -n "$url" ]; then
        echo -e "    ${GREEN}✓${NC} Success"

        # Add comma if not first successful entry
        if [ $SUCCESS_COUNT -gt 0 ]; then
            echo "," >> "$OUTPUT_FILE"
        fi

        # Write to JSON (escape quotes in URL)
        echo -n "    \"$game\": \"$url\"" >> "$OUTPUT_FILE"
        ((SUCCESS_COUNT++))
    else
        echo -e "    ${RED}✗${NC} Failed"
        ((FAIL_COUNT++))
    fi

    # Small delay to avoid rate limiting
    sleep 0.5
done

# Close JSON
echo "" >> "$OUTPUT_FILE"
echo "  }," >> "$OUTPUT_FILE"
echo "  \"stats\": {" >> "$OUTPUT_FILE"
echo "    \"success\": $SUCCESS_COUNT," >> "$OUTPUT_FILE"
echo "    \"failed\": $FAIL_COUNT" >> "$OUTPUT_FILE"
echo "  }" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Summary                                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Total Games:    $GAME_COUNT"
echo -e "Successful:     ${GREEN}$SUCCESS_COUNT${NC}"
echo -e "Failed:         ${RED}$FAIL_COUNT${NC}"
echo ""
echo -e "URLs saved to:  ${CYAN}$OUTPUT_FILE${NC}"
echo ""

# Create a simple list version too
LIST_FILE="game-urls-list.txt"
echo "# Game URLs - Generated at $TIMESTAMP" > "$LIST_FILE"
echo "# Total: $SUCCESS_COUNT games" >> "$LIST_FILE"
echo "" >> "$LIST_FILE"

# Extract URLs from JSON (simple grep method)
grep -o '"[^"]*": "http[^"]*"' "$OUTPUT_FILE" | while IFS= read -r line; do
    game=$(echo "$line" | cut -d'"' -f2)
    url=$(echo "$line" | cut -d'"' -f4)
    echo "$game|$url" >> "$LIST_FILE"
done

echo -e "List format:    ${CYAN}$LIST_FILE${NC}"
echo ""
