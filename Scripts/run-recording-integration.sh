#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
exec bash "$ROOT/Scripts/run-isolated-integration.sh" recording
