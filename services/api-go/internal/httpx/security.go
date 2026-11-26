package httpx

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// SecurityHeaders sets conservative defaults for an API (no framing, no sniffing, no referrer, no caching of responses).
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		h.Set("Cache-Control", "no-store")
		if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
			h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		next.ServeHTTP(w, r)
	})
}

// Limits configures RateLimit. A zero limit disables that bucket.
type Limits struct {
	PerMinute     int  // all API calls per client
	AuthPerMinute int  // /v1/auth/* (login, register, refresh) per client: brute-force protection
	TrustProxy    bool // take the client IP from X-Forwarded-For (only behind a trusted reverse proxy)
}

type bucket struct {
	start time.Time
	n     int
}

type limiter struct {
	mu   sync.Mutex
	m    map[string]*bucket
	now  func() time.Time
	last time.Time
}

func (l *limiter) allow(key string, limit int) (ok bool, retry time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if now.Sub(l.last) > time.Minute { // drop expired windows so the map cannot grow without bound
		for k, b := range l.m {
			if now.Sub(b.start) >= time.Minute {
				delete(l.m, k)
			}
		}
		l.last = now
	}
	b := l.m[key]
	if b == nil || now.Sub(b.start) >= time.Minute {
		b = &bucket{start: now}
		l.m[key] = b
	}
	b.n++
	if b.n > limit {
		return false, b.start.Add(time.Minute).Sub(now)
	}
	return true, 0
}

// ClientIP returns the caller address; X-Forwarded-For's first hop is used only when trustProxy is set.
func ClientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if v := r.Header.Get("X-Forwarded-For"); v != "" {
			first, _, _ := strings.Cut(v, ",")
			if ip := strings.TrimSpace(first); net.ParseIP(ip) != nil {
				return ip
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// RateLimit applies fixed-window per-client limits in memory (single instance; use a shared store before scaling out).
// Health checks and PSP webhooks are exempt: they are machine traffic authenticated by other means.
func RateLimit(next http.Handler, lim Limits) http.Handler {
	return rateLimit(next, lim, time.Now)
}

func rateLimit(next http.Handler, lim Limits, now func() time.Time) http.Handler {
	l := &limiter{m: map[string]*bucket{}, now: now}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if strings.HasPrefix(p, "/health/") || strings.HasPrefix(p, "/v1/webhooks/") {
			next.ServeHTTP(w, r)
			return
		}
		ip := ClientIP(r, lim.TrustProxy)
		check := func(key string, limit int) bool {
			if limit <= 0 {
				return true
			}
			ok, retry := l.allow(key, limit)
			if !ok {
				secs := int(retry.Seconds()) + 1
				w.Header().Set("Retry-After", strconv.Itoa(secs))
				WriteProblem(w, r, http.StatusTooManyRequests, CodeRateLimited, "Too Many Requests", "rate limit exceeded, retry later")
			}
			return ok
		}
		if strings.HasPrefix(p, "/v1/auth/") && !check("auth|"+ip, lim.AuthPerMinute) {
			return
		}
		if !check("all|"+ip, lim.PerMinute) {
			return
		}
		next.ServeHTTP(w, r)
	})
}
