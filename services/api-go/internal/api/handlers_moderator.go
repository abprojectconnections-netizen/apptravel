package api

import (
	"net/http"

	"github.com/Bas-travel/tep/services/api-go/internal/httpx"
)

// moderatorRoutes: the community-moderation portal (/moderator/v1). Moderators and admins may use it; every action is audited.
func (s *Server) moderatorRoutes(m *http.ServeMux) {
	p := s.portal(RoleModerator, RoleAdmin)
	m.HandleFunc("GET /moderator/v1/dashboard", p(s.modDashboard))
	m.HandleFunc("GET /moderator/v1/reports", p(s.adminListReports))
	m.HandleFunc("POST /moderator/v1/reports/{postId}/dismiss", p(func(w http.ResponseWriter, r *http.Request, a actor) {
		s.dismissReports(w, r, a, "moderator.report.dismiss")
	}))
	m.HandleFunc("POST /moderator/v1/reports/{postId}/remove", p(func(w http.ResponseWriter, r *http.Request, a actor) {
		s.removeReportedPost(w, r, a, "moderator.post.remove")
	}))
}

// modDashboard summarises the open moderation queue.
func (s *Server) modDashboard(w http.ResponseWriter, r *http.Request, a actor) {
	var posts, reports int
	var worst *PostReportRow
	err := s.repo.Tx(r.Context(), func(tx Tx) error {
		for off := 0; ; off += 100 {
			rows, total, e := tx.PostReports(off, 100)
			if e != nil {
				return e
			}
			posts = total
			for i := range rows {
				reports += rows[i].Reports
				if worst == nil || rows[i].Reports > worst.Reports {
					cp := rows[i]
					worst = &cp
				}
			}
			if off+100 >= total {
				return nil
			}
		}
	})
	if s.fail(w, r, err) {
		return
	}
	httpx.WriteJSON(w, 200, map[string]any{"reportedPosts": posts, "openReports": reports, "mostReported": worst})
}
