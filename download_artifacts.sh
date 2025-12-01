#!/bin/bash

# Download CI artifacts from GitHub Actions
# Usage: ./download_artifacts.sh [workflow-run-id] [output-dir]
# If workflow-run-id is omitted, uses the latest successful run
# If output-dir is omitted, uses ./artifacts

set -e

# Helper function to extract repo info from git remote
extract_repo_info() {
  local remote_url="$1"
  local owner repo

  # Remove trailing .git if present
  remote_url="${remote_url%.git}"

  # Try to extract owner/repo from various formats
  # SSH: git@github.com:owner/repo
  if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/(.+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  # HTTPS: https://github.com/owner/repo
  elif [[ "$remote_url" =~ https?://[^/]+/([^/]+)/([^/]+)/?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  # Fallback: just owner/repo
  elif [[ "$remote_url" =~ ^([^/]+)/([^/]+)/?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  echo "$owner" "$repo"
  return 0
}

# Configuration
if [ -n "$REPO_OWNER" ] && [ -n "$REPO_NAME" ]; then
  # Use environment variables if provided
  REPO_OWNER="$REPO_OWNER"
  REPO_NAME="$REPO_NAME"
else
  # Try to get from git remote
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")

  if [ -n "$remote_url" ]; then
    repo_info=$(extract_repo_info "$remote_url")
    if [ $? -eq 0 ]; then
      REPO_OWNER=$(echo "$repo_info" | awk '{print $1}')
      REPO_NAME=$(echo "$repo_info" | awk '{print $2}')
    fi
  fi
fi

WORKFLOW_RUN_ID="${1}"
OUTPUT_DIR="${2:-.}/artifacts"
ARTIFACTS=(
  "libpg_query-linux-x64"
  "libpg_query-macos"
  "libpg_query-windows-msvc-x64"
  "libpg_query-windows-msvc-x86"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
  print_error "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com"
  exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
  print_error "Not authenticated with GitHub. Run: gh auth login"
  exit 1
fi

# Validate repository info
if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
  print_error "Could not determine repository information."
  echo ""
  echo "Please set environment variables:"
  echo "  export REPO_OWNER='your-github-username'"
  echo "  export REPO_NAME='libpg_query_ngx_fork'"
  echo ""
  echo "Or fix your git remote:"
  echo "  git remote -v"
  echo "  git remote set-url origin https://github.com/OWNER/REPO.git"
  exit 1
fi

print_info "Repository: $REPO_OWNER/$REPO_NAME"

# If workflow run ID not provided, get the latest successful run
if [ -z "$WORKFLOW_RUN_ID" ]; then
  print_info "Fetching latest successful CI workflow run..."
  WORKFLOW_RUN_ID=$(gh run list \
    --repo "$REPO_OWNER/$REPO_NAME" \
    --workflow ci.yml \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId')

  if [ -z "$WORKFLOW_RUN_ID" ] || [ "$WORKFLOW_RUN_ID" = "null" ]; then
    print_error "No successful workflow runs found. Run a build first!"
    exit 1
  fi
fi

print_info "Workflow run ID: $WORKFLOW_RUN_ID"

# Create output directory
mkdir -p "$OUTPUT_DIR"
print_info "Output directory: $OUTPUT_DIR"

# Download each artifact
failed_count=0
for artifact in "${ARTIFACTS[@]}"; do
  print_info "Downloading: $artifact"

  if gh run download "$WORKFLOW_RUN_ID" \
    --repo "$REPO_OWNER/$REPO_NAME" \
    --name "$artifact" \
    --dir "$OUTPUT_DIR/$artifact" 2>/dev/null; then
    print_success "Downloaded: $artifact"
  else
    print_error "Failed to download: $artifact"
    ((failed_count++))
  fi
done

# Summary
echo ""
print_info "Download complete!"

if [ $failed_count -eq 0 ]; then
  print_success "All 4 artifacts downloaded successfully!"
  echo ""
  echo "Contents:"
  find "$OUTPUT_DIR" -type f -name "*.a" -o -name "*.so" -o -name "*.dylib" -o -name "*.dll" | sed "s|^|  |"
else
  print_warning "$failed_count artifacts failed to download"
  exit 1
fi

