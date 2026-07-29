#!/usr/bin/env bash
# スクロール（単一 WS 接続ドラッグのラッパー）。
#
#   scroll.sh down            # 下方向（ページ下＝後続コンテンツを表示。指は上スワイプ）
#   scroll.sh up              # 上方向（ページ上へ戻す）
#   scroll.sh down fast       # 慣性ありの高速（既定は低速 delay=90 で行き過ぎ抑制）
#   scroll.sh down short      # 振り幅を小さく（短いページ / 微調整用）
#   scroll.sh -d <device> down
#
# ※ ここでの up/down は「見たいコンテンツの方向」。down=ページを下へ進める。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: scroll.sh [-d device] <up|down> [fast|slow] [short|long]" >&2; exit 2; }

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"
# 方向は必須（省略を黙って down に既定化すると引数の取り違えがそのまま通ってしまう）
[ "$#" -ge 1 ] || usage
direction="$1"; shift

delay=90          # 既定は低速（fling 抑制）。fast 指定で 16
amp="long"        # 振り幅。short 指定で小さく
for opt in "$@"; do
  case "$opt" in
    fast) delay=16 ;;
    slow) delay=90 ;;
    short) amp="short" ;;
    long) amp="long" ;;
    *) usage ;;  # typo を黙って既定値で流さない
  esac
done

# 振り幅に応じた begin→move→end の y 並び（x は中央 0.5 固定）
if [ "$amp" = "short" ]; then
  ys_down="0.60 0.50 0.45 0.42"; ys_up="0.42 0.50 0.55 0.60"
else
  ys_down="0.75 0.55 0.35 0.25"; ys_up="0.25 0.45 0.65 0.75"
fi
case "$direction" in
  down) ys="$ys_down" ;;
  up)   ys="$ys_up" ;;
  *) usage ;;
esac

# y 並びから events JSON を組み立て（先頭=begin / 末尾=end / 中間=move）
events=$(printf '%s\n' $ys | awk '
  { y[NR]=$1 }
  END {
    printf "["
    for (i=1;i<=NR;i++) {
      t = (i==1) ? "begin" : (i==NR ? "end" : "move")
      printf "%s{\"type\":\"%s\",\"x\":0.5,\"y\":%s}", (i>1?",":""), t, y[i]
    }
    printf "]"
  }')

sim_resolve_or_die "$SIM_DEV"
sim_gesture "$events" "$delay"
