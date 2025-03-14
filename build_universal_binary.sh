#!/bin/zsh
set -e

# Create temporary files for both architectures
tmp_x86=$(mktemp)
tmp_arm=$(mktemp)

# Cleanup function to remove temp files
cleanup() {
  rm -f "$tmp_x86" "$tmp_arm"
}

# Register cleanup to run on exit
trap cleanup EXIT

# Compile for x86_64 architecture
swiftc ./source/list_workflow.swift \
  -target x86_64-apple-macos10.15 \
  -o "$tmp_x86"

# Compile for arm64 architecture
swiftc ./source/list_workflow.swift \
  -target arm64-apple-macos10.15 \
  -o "$tmp_arm"

# Create output directory if it doesn't exist
mkdir -p ./workflow

# Create universal binary using lipo
lipo -create "$tmp_x86" "$tmp_arm" \
  -output ./workflow/list_workflow

# Set executable permissions
chmod +x ./workflow/list_workflow

echo "Universal binary created at: ./workflow/list_workflow"