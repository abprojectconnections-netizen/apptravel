package httpx

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func ok(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) }

func hit(h http.Handler, path, remote string, hdr ...string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("GET", path, nil)
	r.RemoteAddr = remote
	for i := 0; i+1 < len(hdr); i += 2 {
		r.Header.Set(hdr[i], hdr[i+1])
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestSecurityHeaders(t *testing.T) {
	h := SecurityHeaders(http.HandlerFunc(ok))
	w := hit(h, "/v1/x", "1.1.1.1:1")
	for _, k := range []string{"X-Content-Type-Options", "X-Frame-Options", "Referrer-Policy", "Content-Security-Policy", "Cache-Control"} {
		if w.Header().Get(k) == "" {
			t.Fatal("missing", k)
		}
	}
	if w.Header().Get("Strict-Transport-Security") != "" {
		t.Fatal("HSTS must not be sent over plain HTTP")
	}
	if hit(h, "/v1/x", "1.1.1.1:1", "X-Forwarded-Proto", "https").Header().Get("Strict-Transport-Security") == "" {
		t.Fatal("HSTS expected behind TLS proxy")
	}
}

func TestRateLimit(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	h := rateLimit(http.HandlerFunc(ok), Limits{PerMinute: 5, AuthPerMinute: 2}, func() time.Time { return now })
	for i := 0; i < 2; i++ {
		if hit(h, "/v1/auth/login", "1.1.1.1:5").Code != 200 {
			t.Fatal("within auth limit")
		}
	}
	w := hit(h, "/v1/auth/login", "1.1.1.1:5")
	if w.Code != 429 || w.Header().Get("Retry-After") == "" {
		t.Fatal("auth limit", w.Code, w.Header())
	}
	if hit(h, "/v1/auth/login", "2.2.2.2:5").Code != 200 {
		t.Fatal("limits are per client")
	}
	// general limit counts the 2 allowed auth calls above plus these (5 total allowed)
	for i := 0; i < 3; i++ {
		if hit(h, "/v1/catalog/hotels", "1.1.1.1:5").Code != 200 {
			t.Fatal("within general limit", i)
		}
	}
	if hit(h, "/v1/catalog/hotels", "1.1.1.1:5").Code != 429 {
		t.Fatal("general limit")
	}
	if hit(h, "/health/live", "1.1.1.1:5").Code != 200 || hit(h, "/v1/webhooks/payments/stripe", "1.1.1.1:5").Code != 200 {
		t.Fatal("health and webhooks are exempt")
	}
	now = now.Add(61 * time.Second)
	if hit(h, "/v1/auth/login", "1.1.1.1:5").Code != 200 {
		t.Fatal("window must reset")
	}
}

func TestClientIP(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "9.9.9.9:1"
	r.Header.Set("X-Forwarded-For", "3.3.3.3, 10.0.0.1")
	if ClientIP(r, false) != "9.9.9.9" {
		t.Fatal("XFF must be ignored unless trusted")
	}
	if ClientIP(r, true) != "3.3.3.3" {
		t.Fatal("trusted XFF")
	}
	r.Header.Set("X-Forwarded-For", "not-an-ip")
	if ClientIP(r, true) != "9.9.9.9" {
		t.Fatal("garbage XFF falls back to the socket address")
	}
}
