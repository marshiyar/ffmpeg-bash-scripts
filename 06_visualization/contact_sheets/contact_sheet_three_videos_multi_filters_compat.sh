#!/usr/bin/env bash
# Compatibility wrapper to run the maintained multi-filter script.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
exec ./contact_sheet_three_videos_multi_filters.sh "$@"
