#!/usr/bin/env bash
# 在室判定。anchor のいずれかが画面内ラベル（AXLabel/AXValue/AXPlaceholderValue）に
# 部分一致すれば在室とみなす。在室なら exit 0、非在室なら exit 1、AX 取得異常は exit 2。
#
#   anchor.sh "利用履歴" "アカウント設定"
#   anchor.sh -d <device> "キーワードで検索"
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: anchor.sh [-d device] <anchor> [anchor ...]" >&2; exit 2; }

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"
[ "$#" -ge 1 ] || usage

sim_resolve_or_die "$SIM_DEV"
exec python3 "$DIR/ax_tools.py" --base "$SIM_BASE" anchor "$@"
