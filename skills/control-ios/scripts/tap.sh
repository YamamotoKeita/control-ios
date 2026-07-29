#!/usr/bin/env bash
# タップ。座標変換はスクリプト側で行うので、呼び出し側は AX ラベル / AX ポイント座標 /
# 正規化座標のいずれかで指定すればよい。
#
#   tap.sh --label "ホーム"      # ラベルを AX から解決して tap（exact 一致のみ）
#   tap.sh --label "編集" --type Button   # 同名複数一致を要素タイプで絞る
#   tap.sh --label "削除" --index 2       # 同名複数一致の N番目（1始まり）を選ぶ
#   tap.sh --point 201 437       # AX ポイント座標（root frame で正規化して tap）
#   tap.sh --norm 0.5 0.5        # 既に正規化済みの座標をそのまま tap
#   tap.sh -d <device> --label "設定"
#
# ラベル未発見 / 完全一致が複数（--type/--index 未指定）/ 画面外座標のときは
# tap せず exit 1（推測タップしない）。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: tap.sh [-d device] --label <text> [--type <Type>] [--index <N>] | --point <px> <py> | --norm <nx> <ny>" >&2; exit 2; }

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"
mode="${1:-}"; shift || true

sim_resolve_or_die "$SIM_DEV"

case "$mode" in
  --label)
    [ "$#" -ge 1 ] || usage
    label_text="$1"; shift
    # ax_tools.py へ転送するのは --type <Type> / --index <N> のみ。
    # それ以外（--all 等）は座標1組を返さず read が壊れた値を掴むため弾く
    extra=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --type|--index) [ "$#" -ge 2 ] || usage; extra+=("$1" "$2"); shift 2 ;;
        *) usage ;;
      esac
    done
    coord=$(python3 "$DIR/ax_tools.py" --base "$SIM_BASE" label "$label_text" ${extra[@]+"${extra[@]}"})
    ;;
  --point)
    [ "$#" -ge 2 ] || usage
    coord=$(python3 "$DIR/ax_tools.py" --base "$SIM_BASE" point "$1" "$2")
    ;;
  --norm)
    [ "$#" -ge 2 ] || usage
    awk -v x="$1" -v y="$2" 'BEGIN { exit !(x >= 0 && x <= 1 && y >= 0 && y <= 1) }' \
      || { echo "--norm は 0..1 の範囲で指定してください: $1 $2（画面外はタップしない）" >&2; exit 1; }
    coord="$1 $2"
    ;;
  *) usage ;;
esac

read -r NX NY <<<"$coord"
npx "$SERVE_SIM_PKG" tap "$NX" "$NY" $(sim_dflag)
echo "タップ: $NX $NY"
