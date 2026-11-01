// Package hub keeps one WebSocket per connected device. It relays playback
// state and remote commands between devices (Spotify Connect style) and
// tells every device when shared data changes (library, playlists,
// favourites) so they refresh without polling.
//
// Protocol: JSON text frames with a "type" field.
//
// Client → server:
//
//	{"type":"state","state":{…}}                         playback state snapshot (opaque to the server)
//	{"type":"command","target":7,"action":"pause","args":{…}}  forwarded to device 7
//
// Server → client:
//
//	{"type":"hello","device_id":3,"devices":[{id,name,platform,state}]}  on connect: who is online
//	{"type":"presence","device":{id,name,platform},"online":true}
//	{"type":"state","device_id":7,"state":{…}}
//	{"type":"command","from":3,"action":"pause","args":{…}}
//	{"type":"changed","what":"playlists"}                library | playlists | favorites
//	{"type":"error","error":"device offline"}
package hub

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"

	"ttyfm/internal/store"
)

const (
	pingInterval = 30 * time.Second
	writeTimeout = 10 * time.Second
	sendBuffer   = 64
	maxMessage   = 4 << 20 // a "load" command carries a whole queue
)

// DeviceInfo is what other devices see of a connected device.
type DeviceInfo struct {
	ID       int64           `json:"id"`
	Name     string          `json:"name"`
	Platform string          `json:"platform"`
	State    json.RawMessage `json:"state,omitempty"`
}

type client struct {
	dev  store.Device
	send chan []byte
	conn *websocket.Conn
}

type Hub struct {
	log *slog.Logger

	mu      sync.Mutex
	clients map[int64]*client         // by device id; one connection per device
	states  map[int64]json.RawMessage // last playback state of online devices
}

func New(log *slog.Logger) *Hub {
	return &Hub{log: log, clients: map[int64]*client{}, states: map[int64]json.RawMessage{}}
}

// Serve upgrades the request and runs the connection until it closes.
func (h *Hub) Serve(w http.ResponseWriter, r *http.Request, dev store.Device) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return // Accept already wrote the HTTP error
	}
	conn.SetReadLimit(maxMessage)
	c := &client{dev: dev, send: make(chan []byte, sendBuffer), conn: conn}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	h.register(c)
	defer h.unregister(c)
	go h.writeLoop(ctx, c)
	h.readLoop(ctx, c)
}

func (h *Hub) register(c *client) {
	h.mu.Lock()
	old := h.clients[c.dev.ID]
	h.clients[c.dev.ID] = c
	devices := make([]DeviceInfo, 0, len(h.clients))
	for id, o := range h.clients {
		if id != c.dev.ID && o.dev.UserID == c.dev.UserID {
			devices = append(devices, h.info(o))
		}
	}
	h.mu.Unlock()
	if old != nil {
		old.conn.Close(websocket.StatusPolicyViolation, "replaced by a newer connection")
	}
	c.push(map[string]any{"type": "hello", "device_id": c.dev.ID, "devices": devices})
	h.toOthers(c.dev, map[string]any{"type": "presence", "device": h.info(c), "online": true})
	h.log.Debug("hub: connected", "device", c.dev.ID, "name", c.dev.Name)
}

func (h *Hub) unregister(c *client) {
	h.mu.Lock()
	if h.clients[c.dev.ID] != c {
		h.mu.Unlock() // replaced by a newer connection: nothing to announce
		return
	}
	delete(h.clients, c.dev.ID)
	delete(h.states, c.dev.ID)
	h.mu.Unlock()
	h.toOthers(c.dev, map[string]any{"type": "presence", "device": h.info(c), "online": false})
	h.log.Debug("hub: disconnected", "device", c.dev.ID)
}

// info must be called with h.mu held, or for a client not in the map.
func (h *Hub) info(c *client) DeviceInfo {
	return DeviceInfo{ID: c.dev.ID, Name: c.dev.Name, Platform: c.dev.Platform, State: h.states[c.dev.ID]}
}

type inMsg struct {
	Type   string          `json:"type"`
	State  json.RawMessage `json:"state"`
	Target int64           `json:"target"`
	Action string          `json:"action"`
	Args   json.RawMessage `json:"args"`
}

func (h *Hub) readLoop(ctx context.Context, c *client) {
	for {
		_, data, err := c.conn.Read(ctx)
		if err != nil {
			return
		}
		var m inMsg
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		switch m.Type {
		case "state":
			h.mu.Lock()
			h.states[c.dev.ID] = m.State
			h.mu.Unlock()
			h.toOthers(c.dev, map[string]any{"type": "state", "device_id": c.dev.ID, "state": m.State})
		case "command":
			h.mu.Lock()
			target := h.clients[m.Target]
			h.mu.Unlock()
			if target == nil || target.dev.UserID != c.dev.UserID {
				c.push(map[string]any{"type": "error", "error": "device offline", "target": m.Target})
				continue
			}
			target.push(map[string]any{"type": "command", "from": c.dev.ID, "action": m.Action, "args": m.Args})
		}
	}
}

func (h *Hub) writeLoop(ctx context.Context, c *client) {
	ping := time.NewTicker(pingInterval)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case b := <-c.send:
			wctx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Write(wctx, websocket.MessageText, b)
			cancel()
			if err != nil {
				c.conn.CloseNow()
				return
			}
		case <-ping.C:
			pctx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Ping(pctx)
			cancel()
			if err != nil {
				c.conn.CloseNow()
				return
			}
		}
	}
}

// push queues a message; a client too slow to keep up is disconnected
// (it reconnects and gets a fresh hello).
func (c *client) push(v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	select {
	case c.send <- b:
	default:
		c.conn.CloseNow()
	}
}

func (h *Hub) toOthers(dev store.Device, v any) {
	h.mu.Lock()
	targets := make([]*client, 0, len(h.clients))
	for id, c := range h.clients {
		if id != dev.ID && c.dev.UserID == dev.UserID {
			targets = append(targets, c)
		}
	}
	h.mu.Unlock()
	for _, c := range targets {
		c.push(v)
	}
}

// Changed tells every connected device that shared data changed. what is
// "library", "playlists" or "favorites". The originating device (0 for the
// server itself) is skipped: it already refreshed.
func (h *Hub) Changed(what string, origin int64) {
	h.mu.Lock()
	targets := make([]*client, 0, len(h.clients))
	for id, c := range h.clients {
		if id != origin {
			targets = append(targets, c)
		}
	}
	h.mu.Unlock()
	for _, c := range targets {
		c.push(map[string]any{"type": "changed", "what": what})
	}
}

// Online reports the number of connected devices.
func (h *Hub) Online() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.clients)
}
