#!/bin/bash
# Update Roblox type definitions for luau-lsp

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TYPES_DIR="$ROOT_DIR/types"

mkdir -p "$TYPES_DIR"

echo "Downloading latest Roblox type definitions..."

# Global types (classes, enums, etc)
curl -sL -o "$TYPES_DIR/globalTypes.d.luau" \
  "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

# API documentation
curl -sL -o "$TYPES_DIR/api-docs.json" \
  "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/api-docs/en-us.json"

echo "Done. Types updated in $TYPES_DIR"
ls -la "$TYPES_DIR"
