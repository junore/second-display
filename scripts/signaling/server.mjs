import http from 'http';
import { WebSocketServer } from 'ws';

const PORT = process.env.PORT || 8080;
const server = http.createServer();
const wss = new WebSocketServer({ server });

let mac = null;
let android = null;

function send(ws, obj) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

wss.on('connection', (ws) => {
  let role = null;

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type === 'hello' && (msg.role === 'mac' || msg.role === 'android')) {
        role = msg.role;
        if (role === 'mac') mac = ws;
        if (role === 'android') android = ws;
        send(ws, { type: 'hello-ack', role });
        return;
      }
      const peer = role === 'mac' ? android : mac;
      if (!peer) return;
      send(peer, msg);
    } catch (e) {
      console.error('Bad message', e);
    }
  });

  ws.on('close', () => {
    if (role === 'mac') mac = null;
    if (role === 'android') android = null;
  });
});

server.listen(PORT, () => {
  console.log(`Signaling server on ws://0.0.0.0:${PORT}`);
});
