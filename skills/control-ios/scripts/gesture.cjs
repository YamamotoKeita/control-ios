// 単一 WebSocket 接続で begin→move×N→end を連続送信するドラッグ。
// CLI の `gesture` を複数回呼ぶと接続が分断され long-press 化するため、確実な多段ドラッグはこちらを使う。
//
//   NODE_PATH=<ws の親dir> node gesture.cjs <wsUrl> '<eventsJSON>' [delayMs]
//
//   <eventsJSON> 例: [{"type":"begin","x":0.5,"y":0.7},{"type":"move",...},{"type":"end","x":0.5,"y":0.3}]
//   [delayMs] move 間隔。既定 16=高速 / 80〜90=低速（fling 抑制）
const WebSocket = require("ws");
const url = process.argv[2];
const events = JSON.parse(process.argv[3]);
const delay = parseInt(process.argv[4] || "16", 10);
// TCP は繋がるが WS upgrade が返らないケースで open/error とも発火せず無限ハングするため、
// ハンドシェイクに期限を設ける（超過時は error が発火して exit 1）
const ws = new WebSocket(url, { handshakeTimeout: 10000 });
ws.binaryType = "arraybuffer";
ws.on("open", async () => {
  for (const ev of events) {
    const b = Buffer.from(JSON.stringify(ev), "utf8");
    ws.send(Buffer.concat([Buffer.from([3]), b])); // 0x03 = JSON touch
    await new Promise((r) => setTimeout(r, delay));
  }
  setTimeout(() => { ws.close(); console.log("送信完了"); }, 120);
});
ws.on("error", (e) => { console.error("WS エラー:", e.message); process.exit(1); });
