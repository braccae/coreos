#!/usr/bin/env bash

# A script to download a file from the latest GitHub release by matching multiple substrings.
#
# Usage: ./get_latest_release_finetuned.sh <GITHUB_REPO_URL> <SEARCH_STRING_1> [SEARCH_STRING_2] ...
#
# The script will find the asset whose filename contains ALL of the provided search strings.
# The search is case-insensitive.
#
# Example (find an RPM for the current kernel):
#   ./get_latest_release_finetuned.sh https://github.com/45drives/cockpit-identities rpm "$(uname -r)"
#
# Example (find a .deb for Ubuntu Focal):
#   ./get_latest_release_finetuned.sh https://github.com/45drives/cockpit-identities .deb focal

# --- Configuration & Safety ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Functions ---
usage() {
    echo "Usage: $0 <GITHUB_REPO_URL> <SEARCH_STRING_1> [SEARCH_STRING_2] ..."
    echo "The script will find the asset whose filename contains ALL of the provided search strings (case-insensitive)."
    echo "Example: $0 https://github.com/owner/repo rpm \"\$(uname -r)\""
    echo "Example: $0 https://github.com/owner/repo .deb focal"
    exit 1
}

# --- Argument Parsing ---
if [ "$#" -lt 2 ]; then
    usage
fi

REPO_URL="$1"
shift # Remove the URL from the arguments list, leaving only the search strings
SEARCH_STRINGS=("$@")

# Extract the owner/repo part from the URL (e.g., "owner/repo")
OWNER_REPO=$(echo "$REPO_URL" | sed -e 's|.*github.com/||' -e 's|/$||')

if [ -z "$OWNER_REPO" ] || [[ "$OWNER_REPO" != *"/"* ]]; then
    echo "Error: Invalid GitHub repository URL provided."
    usage
fi

API_URL="https://api.github.com/repos/${OWNER_REPO}/releases/latest"
TEMP_JSON_FILE=$(mktemp)

# --- Main Logic ---
echo "Fetching latest release info for '${OWNER_REPO}'..."
echo "Searching for files containing all of these strings: ${SEARCH_STRINGS[*]}"
echo "--------------------------------------------------"

# Use curl to fetch the release data
HTTP_STATUS=$(curl -sL -o "$TEMP_JSON_FILE" -w "%{http_code}" -H "Accept: application/vnd.github.v3+json" -H "User-Agent: get-latest-release-script" "$API_URL")

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "Error: Failed to fetch release info. HTTP Status: $HTTP_STATUS"
    if [ -s "$TEMP_JSON_FILE" ]; then
        echo "Response from GitHub:"
        jq -r '.message' "$TEMP_JSON_FILE" 2>/dev/null || cat "$TEMP_JSON_FILE"
    fi
    rm -f "$TEMP_JSON_FILE"
    exit 1
fi

# Extract information using jq
TAG_NAME=$(jq -r '.tag_name' "$TEMP_JSON_FILE")
echo "Found latest release tag: ${TAG_NAME}"
echo "--------------------------------------------------"

ASSET_NAMES=$(jq -r '.assets[].name' "$TEMP_JSON_FILE")
DOWNLOAD_URLS=()

for ASSET_NAME in $ASSET_NAMES; do
    MATCH=true
    LOWER_ASSET_NAME=$(echo "$ASSET_NAME" | tr '[:upper:]' '[:lower:]')
    for SEARCH_STRING in "${SEARCH_STRINGS[@]}"; do
        LOWER_SEARCH_STRING=$(echo "$SEARCH_STRING" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$LOWER_ASSET_NAME" =~ $LOWER_SEARCH_STRING ]]; then
            MATCH=false
            break
        fi
    done
    if [ "$MATCH" = true ]; then
        # Found a match, get its download URL
        URL=$(jq -r ".assets[] | select(.name == \"$ASSET_NAME\") | .browser_download_url" "$TEMP_JSON_FILE")
        if [ -n "$URL" ]; then
            DOWNLOAD_URLS+=("$URL")
        fi
    fi
done

if [ -z "$DOWNLOAD_URLS" ]; then
    echo "No files found matching all criteria: ${SEARCH_STRINGS[*]}"
    echo "Available files in this release:"
    jq -r '.assets[].name' "$TEMP_JSON_FILE"
    rm -f "$TEMP_JSON_FILE"
    exit 1
fi

echo "Found matching file(s). Starting download..."
# Download each found file
for URL in "${DOWNLOAD_URLS[@]}"; do
    FILENAME=$(basename "$URL")
    echo "  -> Downloading ${FILENAME}..."
    curl -L -o "$FILENAME" "$URL"
done

echo "--------------------------------------------------"
echo "Log of all release assets for record:"
jq -r '.assets[] | "- \(.name) (size: \(.size | floor / 1048576) MB)"' "$TEMP_JSON_FILE"
echo "--------------------------------------------------"
echo "Download complete."

# Clean up
rm -f "$TEMP_JSON_FILE"