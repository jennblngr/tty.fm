// Package auth handles the single user's password (argon2id) and opaque
// per-device bearer tokens.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/argon2"

	"ttyfm/internal/store"
)

// argon2id parameters (OWASP baseline). ~50 ms on an N100.
const (
	argonTime    = 2
	argonMemory  = 19 * 1024
	argonThreads = 1
	argonKeyLen  = 32
)

var ErrBadCredentials = errors.New("bad credentials")

// HashPassword returns a PHC-formatted argon2id hash.
func HashPassword(pw string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := argon2.IDKey([]byte(pw), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	b64 := base64.RawStdEncoding
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonTime, argonThreads, b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

// VerifyPassword checks pw against a PHC argon2id hash.
func VerifyPassword(pw, hash string) bool {
	parts := strings.Split(hash, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}
	var m, t uint32
	var p uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &m, &t, &p); err != nil {
		return false
	}
	b64 := base64.RawStdEncoding
	salt, err := b64.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := b64.DecodeString(parts[5])
	if err != nil {
		return false
	}
	got := argon2.IDKey([]byte(pw), salt, t, m, p, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}

func hashToken(tok string) string {
	h := sha256.Sum256([]byte(tok))
	return hex.EncodeToString(h[:])
}

func newToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

type cached struct {
	dev      store.Device
	until    time.Time
	lastSeen time.Time
}

type Service struct {
	db  *store.DB
	log *slog.Logger

	mu    sync.Mutex
	cache map[string]*cached // token hash → device
}

func NewService(db *store.DB, log *slog.Logger) *Service {
	return &Service{db: db, log: log, cache: map[string]*cached{}}
}

// EnsureUser creates the user on first start. If a password is configured
// and differs from the stored one, it is updated: the environment is the
// source of truth for this single-user server.
func (s *Service) EnsureUser(ctx context.Context, username, password string) error {
	u, err := s.db.UserByName(ctx, username)
	if errors.Is(err, store.ErrNotFound) {
		n, err := s.db.UserCount(ctx)
		if err != nil {
			return err
		}
		if n > 0 {
			return fmt.Errorf("user %q not found but another user exists", username)
		}
		generated := false
		if password == "" {
			if password, err = newToken(); err != nil {
				return err
			}
			password = password[:16]
			generated = true
		}
		hash, err := HashPassword(password)
		if err != nil {
			return err
		}
		if _, err := s.db.CreateUser(ctx, username, hash); err != nil {
			return err
		}
		if generated {
			s.log.Warn("created user with a generated password; set ADMIN_PASSWORD to choose one",
				"user", username, "password", password)
		} else {
			s.log.Info("created user", "user", username)
		}
		return nil
	}
	if err != nil {
		return err
	}
	if password != "" && !VerifyPassword(password, u.PasswordHash) {
		hash, err := HashPassword(password)
		if err != nil {
			return err
		}
		s.log.Info("password updated from environment", "user", username)
		return s.db.SetPassword(ctx, u.ID, hash)
	}
	return nil
}

// Login verifies credentials and registers a new device. The returned token
// is shown once; only its hash is stored.
func (s *Service) Login(ctx context.Context, username, password, deviceName, platform string) (string, store.Device, error) {
	u, err := s.db.UserByName(ctx, username)
	if errors.Is(err, store.ErrNotFound) {
		VerifyPassword(password, "$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
		return "", store.Device{}, ErrBadCredentials
	}
	if err != nil {
		return "", store.Device{}, err
	}
	if !VerifyPassword(password, u.PasswordHash) {
		return "", store.Device{}, ErrBadCredentials
	}
	tok, err := newToken()
	if err != nil {
		return "", store.Device{}, err
	}
	if deviceName == "" {
		deviceName = "Unknown device"
	}
	dev, err := s.db.CreateDevice(ctx, u.ID, deviceName, platform, hashToken(tok))
	return tok, dev, err
}

// Revoke deletes a device; its token stops working immediately.
func (s *Service) Revoke(ctx context.Context, userID, deviceID int64) error {
	if err := s.db.DeleteDevice(ctx, userID, deviceID); err != nil {
		return err
	}
	s.mu.Lock()
	for k, c := range s.cache {
		if c.dev.ID == deviceID {
			delete(s.cache, k)
		}
	}
	s.mu.Unlock()
	return nil
}

// Authenticate resolves a token, caching it for a minute and updating the
// device's last_seen_at at most once a minute.
func (s *Service) Authenticate(ctx context.Context, tok string) (store.Device, error) {
	if tok == "" {
		return store.Device{}, ErrBadCredentials
	}
	h := hashToken(tok)
	now := time.Now()
	s.mu.Lock()
	c, ok := s.cache[h]
	s.mu.Unlock()
	if !ok || now.After(c.until) {
		dev, err := s.db.DeviceByToken(ctx, h)
		if errors.Is(err, store.ErrNotFound) {
			return store.Device{}, ErrBadCredentials
		}
		if err != nil {
			return store.Device{}, err
		}
		c = &cached{dev: dev, until: now.Add(time.Minute), lastSeen: time.Unix(dev.LastSeenAt, 0)}
		s.mu.Lock()
		s.cache[h] = c
		s.mu.Unlock()
	}
	s.mu.Lock()
	touch := now.Sub(c.lastSeen) > time.Minute
	if touch {
		c.lastSeen = now
	}
	s.mu.Unlock()
	if touch {
		if err := s.db.TouchDevice(ctx, c.dev.ID, now); err != nil {
			s.log.Warn("touch device", "err", err)
		}
	}
	return c.dev, nil
}

type ctxKey struct{}

// DeviceFrom returns the authenticated device of a request.
func DeviceFrom(ctx context.Context) store.Device {
	d, _ := ctx.Value(ctxKey{}).(store.Device)
	return d
}

// TokenFrom extracts the bearer token from the Authorization header, or
// from the "token" query parameter (for players that cannot set headers).
func TokenFrom(r *http.Request) string {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	return r.URL.Query().Get("token")
}

// Middleware rejects unauthenticated requests with 401.
func (s *Service) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		dev, err := s.Authenticate(r.Context(), TokenFrom(r))
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("WWW-Authenticate", "Bearer")
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(`{"error":"unauthorized"}`))
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, dev)))
	})
}
