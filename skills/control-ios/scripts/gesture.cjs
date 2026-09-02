// 単一 WebSocket 接続で begin→move×N→end を連続送信するドラッグ / ピンチ。
// CLI の `gesture` を複数回呼ぶと接続が分断され long-press 化するため、確実な多段ドラッグはこちらを使う。
//
//   NODE_PATH=<ws の親dir> node gesture.cjs <wsUrl> '<eventsJSON>' [delayMs]
//
//   <eventsJSON> 例（単指）: [{"type":"begin","x":0.5,"y":0.7},{"type":"move",...},{"type":"end","x":0.5,"y":0.3}]
//   <eventsJSON> 例（2本指）: [{"type":"begin","x1":0.45,"y1":0.45,"x2":0.55,"y2":0.55},{"type":"move",...},{"type":"end",...}]
//   [delayMs] move 間隔。既定 16=高速 / 80〜90=低速（fling 抑制）
//
// serve-sim の WS バイナリフレームは先頭1バイトが opcode:
//   0x03 = 単指タッチ JSON {type,x,y}           → helper の touch()
//   0x05 = 2本指マルチタッチ JSON {type,x1,y1,x2,y2} → helper の multiTouch()
// ピンチは 0x03 を2本ぶん交互に送っても単指ドラッグ（パン）にしかならない。
// x1/x2 を持つイベントは自動で 0x05 に振り分ける。
const WebSocket = require("ws");
const url = process.argv[2];
const events = JSON.parse(process.argv[3]);
const delay = parseInt(process.argv[4] || "16", 10);
const OP_TOUCH = 0x03;
const OP_MULTI_TOUCH = 0x05;
const isMulti = (ev) => ev.x1 != null && ev.x2 != null;
// TCP は繋がるが WS upgrade が返らないケースで open/error とも発火せず無限ハングするため、
// ハンドシェイクに期限を設ける（超過時は error が発火して exit 1）
const ws = new WebSocket(url, { handshakeTimeout: 10000 });
ws.binaryType = "arraybuffer";
ws.on("open", async () => {
  for (const ev of events) {
    const b = Buffer.from(JSON.stringify(ev), "utf8");
    const op = isMulti(ev) ? OP_MULTI_TOUCH : OP_TOUCH;
    ws.send(Buffer.concat([Buffer.from([op]), b]));
    await new Promise((r) => setTimeout(r, delay));
  }
  setTimeout(() => { ws.close(); console.log("送信完了"); }, 120);
});
ws.on("error", (e) => { console.error("WS エラー:", e.message); process.exit(1); });
