#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
python_bin="$project_root/.venv-langgraph/bin/python"

if [[ ! -x "$python_bin" ]]; then
  echo "Run Scripts/setup-langgraph-sidecar.sh first."
  exit 1
fi

cd "$project_root/orchestration"
exec "$python_bin" -m alexi_graph.server
