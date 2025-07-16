#!/usr/bin/env bash
set -euo pipefail

# Get the directory of this script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_file="$script_dir/package.nix"

# Fetch latest version from GitHub API
echo "Fetching latest version..."
latest_version=$(curl -s https://api.github.com/repos/MrLesk/Backlog.md/releases/latest | jq -r '.tag_name' | sed 's/^v//')
echo "Latest version: $latest_version"

# Extract current version from package.nix
current_version=$(grep -E '^\s*version = "' "$package_file" | head -1 | sed -E 's/.*version = "([^"]+)".*/\1/')
echo "Current version: $current_version"

# Check if update is needed
if [ "$latest_version" = "$current_version" ]; then
  echo "Package is already up to date!"
  exit 0
fi

echo "Update available: $current_version -> $latest_version"

# Calculate new source hash
echo "Calculating source hash for new version..."
new_src_hash=$(nix hash file --sri <(curl -sL "https://github.com/MrLesk/Backlog.md/archive/v${latest_version}.tar.gz"))
echo "New source hash: $new_src_hash"

# Create temporary file for updated content
tmp_file=$(mktemp)
cp "$package_file" "$tmp_file"

# Update version
sed -i "s/version = \"${current_version}\";/version = \"${latest_version}\";/" "$tmp_file"

# Update source hash
old_src_hash=$(grep -A3 'src = fetchFromGitHub' "$package_file" | grep 'hash = ' | sed -E 's/.*hash = "([^"]+)".*/\1/')
sed -i "s|$old_src_hash|$new_src_hash|" "$tmp_file"

# Move updated file back
mv "$tmp_file" "$package_file"

echo "Updated version and source hash. Now building to get new node_modules hash..."

# Build with dummy hash to get the correct one
old_node_hash=$(grep -A5 'node_modules = fetchBunDeps' "$package_file" | grep 'hash = ' | sed -E 's/.*hash = "([^"]+)".*/\1/')
sed -i "s|$old_node_hash|sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=|" "$package_file"

# Try to build and capture the correct hash
echo "Building to get correct node_modules hash..."
if output=$(nix build "$script_dir/../.."#packages.x86_64-linux.backlog-md 2>&1); then
  echo "Build succeeded unexpectedly with dummy hash!"
else
  # Extract the correct hash from error output
  if new_node_hash=$(echo "$output" | grep -A1 "got:" | tail -1 | xargs); then
    echo "New node_modules hash: $new_node_hash"
    sed -i "s|sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=|$new_node_hash|" "$package_file"
  else
    echo "ERROR: Could not extract node_modules hash from build output"
    # Restore original hash
    sed -i "s|sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=|$old_node_hash|" "$package_file"
    exit 1
  fi
fi

echo "Building package to verify..."
nix build "$script_dir/../.."#packages.x86_64-linux.backlog-md

echo "Update completed successfully!"
echo "backlog-md has been updated from $current_version to $latest_version"
