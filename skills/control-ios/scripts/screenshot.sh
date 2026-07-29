#!/usr/bin/env bash
# スクリーンショット取得。MJPEG 抽出ではなく simctl の純正スクショを使う
# （高速・フル解像度・JPEG 切り出し不要）。保存先パスを stdout に出力。
#
#   screenshot.sh                 # 既定パスへ保存しパスを表示
#   screenshot.sh /tmp/foo.png    # 保存先を指定
#   screenshot.sh -d <device> out.png
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: screenshot.sh [-d device] [out.png]" >&2; exit 2; }

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"
# 既定名は連続撮影でも衝突しないよう 日付+PID+乱数 を付ける
out="${1:-${TMPDIR:-/tmp}/sim-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM.png}"

sim_resolve_or_die "$SIM_DEV"
# 成功時は simctl の情報メッセージを出さず、失敗時のみ理由を stderr に出す
if ! err=$(xcrun simctl io "$SIM_UDID" screenshot "$out" 2>&1 >/dev/null); then
  printf '%s\n' "$err" >&2
  exit 1
fi
printf '%s\n' "$out"
