#!/usr/bin/env bash
# 日本語テキスト入力（pbcopy + 長押しペースト）。`serve-sim type` は US キーボード固定で
# かな IME 下では崩れるため、確実な日本語入力はこちら。
#
#   type-paste.sh "東京" --label "キーワードで検索"   # 入力欄をラベルで指定
#   type-paste.sh "東京" --norm 0.4 0.117              # 入力欄を正規化座標で指定
#   type-paste.sh -d <device> "東京" --label "..."
#
# 手順: pbcopy → 入力欄を tap でフォーカス → 長押しで編集メニュー → 「ペースト」を tap。
# 「ペースト」が AX で取れなければ座標を案内して終了（手動で tap）。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: type-paste.sh [-d device] <text> --label <text> | --norm <nx> <ny>" >&2; exit 2; }

sim_parse_dev "$@" || usage
shift "$SIM_DEV_SHIFT"
text="${1:-}"; shift || true
mode="${1:-}"; shift || true
[ -n "$text" ] && [ -n "$mode" ] || usage

sim_resolve_or_die "$SIM_DEV"

# 入力欄座標を解決
case "$mode" in
  --label)
    [ "$#" -ge 1 ] || usage
    # here-string 内のコマンド置換だと失敗が set -e に捕捉されないため、代入で受けてから read する
    coord=$(python3 "$DIR/ax_tools.py" --base "$SIM_BASE" label "$1")
    read -r FX FY <<<"$coord"
    ;;
  --norm)
    [ "$#" -ge 2 ] || usage
    awk -v x="$1" -v y="$2" 'BEGIN { exit !(x >= 0 && x <= 1 && y >= 0 && y <= 1) }' \
      || { echo "--norm は 0..1 の範囲で指定してください: $1 $2（画面外は操作しない）" >&2; exit 1; }
    FX="$1"; FY="$2"
    ;;
  *) echo "入力欄指定が不正: $mode" >&2; exit 2 ;;
esac

DFLAG=$(sim_dflag)
printf '%s' "$text" | xcrun simctl pbcopy "$SIM_UDID"   # 改行を入れない
npx "$SERVE_SIM_PKG" tap "$FX" "$FY" $DFLAG              # フォーカス
sleep 0.4
# 長押し（gesture begin/end 分割の癖を利用して編集メニューを出す）
npx "$SERVE_SIM_PKG" gesture "{\"type\":\"begin\",\"x\":$FX,\"y\":$FY}" $DFLAG; sleep 0.7
npx "$SERVE_SIM_PKG" gesture "{\"type\":\"end\",\"x\":$FX,\"y\":$FY}" $DFLAG
sleep 0.5

# 「ペースト」を AX から探して tap（英語ロケールの Simulator ではメニューが「Paste」になるため両方試す）
PX_PY=""
for menu_label in "ペースト" "Paste"; do
  if PX_PY=$(python3 "$DIR/ax_tools.py" --base "$SIM_BASE" label "$menu_label" 2>/dev/null); then
    break
  fi
done
if [ -n "$PX_PY" ]; then
  read -r PX PY <<<"$PX_PY"
  npx "$SERVE_SIM_PKG" tap "$PX" "$PY" $DFLAG
  echo "ペースト完了（${#text}文字）"   # 認証情報等が実行ログに残らないよう値は出さない
else
  echo "「ペースト」を AX で検出できず。スクショで位置を確認し tap.sh --norm で手動ペーストしてください（pbcopy 済み）" >&2
  exit 1
fi
