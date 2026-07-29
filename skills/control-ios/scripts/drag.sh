#!/usr/bin/env bash
# 任意座標の多段ドラッグ。WS 解決と NODE_PATH 設定を隠蔽し、events JSON を渡すだけにする。
# モーダルシートの下スワイプ dismiss など、scroll.sh で表せない動きに使う。
#
#   drag.sh '[{"type":"begin","x":0.5,"y":0.2},{"type":"move","x":0.5,"y":0.6},{"type":"end","x":0.5,"y":0.9}]'
#   drag.sh -d <device> '<eventsJSON>' [delayMs]   # delayMs 既定16=高速 / 80〜90=低速
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: drag.sh [-d device] '<eventsJSON>' [delayMs]" >&2; exit 2; }

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"
events="${1:-}"; delay="${2:-16}"
[ -n "$events" ] || usage

sim_resolve_or_die "$SIM_DEV"
sim_gesture "$events" "$delay"
