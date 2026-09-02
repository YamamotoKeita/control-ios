#!/usr/bin/env bash
# ピンチイン / ピンチアウト（2本指マルチタッチ）。地図・画像のズームに使う。
# 中心 (cx,cy) を挟んで左右に置いた2本指を、中心からの距離 from → to まで N ステップで動かす。
#
#   pinch.sh out                         # 中心 (0.5,0.5) で拡大（中心からの指の距離 0.05 → 0.35）
#   pinch.sh in                          # 中心 (0.5,0.5) で縮小（同 0.35 → 0.05）
#   pinch.sh out --center 0.5 0.4        # 中心を正規化座標で指定
#   pinch.sh in  --from 0.3 --to 0.05    # 中心から各指までの距離（正規化 x）を指定
#   pinch.sh out --steps 30 --delay 30   # 段数 / move 間隔ms（大きいほどゆっくり）
#   pinch.sh -d <device> out
#
# 座標はすべて正規化 0..1（左上 (0,0)〜右下 (1,1)）。2本指は同じ y に (cx-d, cy) と (cx+d, cy) で置く。
# 縦方向に広げると下端の検索バー / シート（Maps 等）や上端の通知センター領域を踏んで
# 別ジェスチャに化けるため、横一列に固定している。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() {
  echo "usage: pinch.sh [-d device] <in|out> [--center cx cy] [--from d] [--to d] [--steps N] [--delay ms]" >&2
  exit 2
}

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"

mode="${1:-}"; [ -n "$mode" ] || usage; shift
cx=0.5; cy=0.5; from=""; to=""; steps=20; delay=30
while [ "$#" -gt 0 ]; do
  case "$1" in
    --center) cx="$2"; cy="$3"; shift 3 ;;
    --from)   from="$2"; shift 2 ;;
    --to)     to="$2"; shift 2 ;;
    --steps)  steps="$2"; shift 2 ;;
    --delay)  delay="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$mode" in
  out) from="${from:-0.05}"; to="${to:-0.35}" ;;
  in)  from="${from:-0.35}"; to="${to:-0.05}" ;;
  *) usage ;;
esac

sim_resolve_or_die "$SIM_DEV"

# 指が画面外に出ると end が届かず「指が張り付いた」状態になるため 0.02..0.98 に丸める
events=$(python3 - "$cx" "$cy" "$from" "$to" "$steps" <<'PY'
import json, sys
cx, cy, d0, d1, n = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
if n < 1:
    n = 1
clamp = lambda v: round(min(0.98, max(0.02, v)), 4)
def fingers(d):
    return {"x1": clamp(cx - d), "y1": clamp(cy), "x2": clamp(cx + d), "y2": clamp(cy)}
evs = [{"type": "begin", **fingers(d0)}]
for i in range(1, n + 1):
    evs.append({"type": "move", **fingers(d0 + (d1 - d0) * i / n)})
evs.append({"type": "end", **fingers(d1)})
print(json.dumps(evs))
PY
)
sim_gesture "$events" "$delay"
