#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
python_bin="${ALEXI_PYTHON:-/opt/homebrew/bin/python3.11}"

if [[ ! -x "$python_bin" ]]; then
  echo "Python 3.11 was not found at $python_bin. Set ALEXI_PYTHON to a Python 3.11+ executable."
  exit 1
fi

"$python_bin" -m venv "$project_root/.venv-langgraph"
"$project_root/.venv-langgraph/bin/python" -m pip install --upgrade pip
"$project_root/.venv-langgraph/bin/python" -m pip install -e "$project_root/orchestration"

echo "LangGraph sidecar installed. Start it with Scripts/run-langgraph-sidecar.sh"
