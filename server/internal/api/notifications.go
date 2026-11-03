package api

import (
	"net/http"
	"time"

	"ttyfm/internal/auth"
)

// --- notifications ---------------------------------------------------------

// Notifications are generated when read: the list and the unread count
// first catch up with the library.

func (s *Server) notifications(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	user := auth.DeviceFrom(ctx).UserID
	if err := s.DB.SyncNotifications(ctx, user, time.Now()); err != nil {
		s.fail(w, r, err)
		return
	}
	items, err := s.DB.Notifications(ctx, user, queryInt(r, "limit", 100))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	unread := 0
	for _, n := range items {
		if !n.Read {
			unread++
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "unread": unread})
}

func (s *Server) unreadNotifications(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	user := auth.DeviceFrom(ctx).UserID
	if err := s.DB.SyncNotifications(ctx, user, time.Now()); err != nil {
		s.fail(w, r, err)
		return
	}
	n, err := s.DB.UnreadNotifications(ctx, user)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"unread": n})
}

func (s *Server) updateNotification(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Read *bool `json:"read"`
	}
	id, err := pathID(r, "id")
	if err == nil {
		err = decode(r, &body)
	}
	if err == nil && body.Read == nil {
		err = errBadRequest
	}
	if err == nil {
		err = s.DB.MarkNotificationRead(r.Context(), auth.DeviceFrom(r.Context()).UserID, id, *body.Read)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) readAllNotifications(w http.ResponseWriter, r *http.Request) {
	if err := s.DB.MarkAllNotificationsRead(r.Context(), auth.DeviceFrom(r.Context()).UserID); err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) notificationSettings(w http.ResponseWriter, r *http.Request) {
	set, err := s.DB.NotificationSettings(r.Context(), auth.DeviceFrom(r.Context()).UserID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, set)
}

// updateNotificationSettings takes {"added": false}, and returns every
// kind's setting.
func (s *Server) updateNotificationSettings(w http.ResponseWriter, r *http.Request) {
	var body map[string]bool
	err := decode(r, &body)
	if err == nil {
		err = s.DB.SetNotificationSettings(r.Context(), auth.DeviceFrom(r.Context()).UserID, body)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.notificationSettings(w, r)
}
