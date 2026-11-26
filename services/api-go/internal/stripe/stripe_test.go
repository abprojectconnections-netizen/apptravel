package stripe

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestValidateKeys(t *testing.T) {
	if ValidateKeys("", "") != nil {
		t.Fatal("disabled must be ok")
	}
	if ValidateKeys("sk_live_abc", "whsec_x") == nil || ValidateKeys("rk_live_abc", "whsec_x") == nil {
		t.Fatal("live keys must be rejected")
	}
	if ValidateKeys("sk_test_abc", "") == nil {
		t.Fatal("webhook secret required")
	}
	if ValidateKeys("sk_test_abc", "whsec_x") != nil {
		t.Fatal("valid test config rejected")
	}
}

func TestVerifySignature(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	body := []byte(`{"id":"evt_1"}`)
	h := Sign(body, "whsec_s", now)
	if err := VerifySignature(body, h, "whsec_s", now, 5*time.Minute); err != nil {
		t.Fatal(err)
	}
	for name, c := range map[string]struct {
		body []byte
		hdr  string
		sec  string
		at   time.Time
	}{
		"tampered":  {[]byte(`{"id":"evt_2"}`), h, "whsec_s", now},
		"wrong key": {body, h, "whsec_other", now},
		"stale":     {body, h, "whsec_s", now.Add(10 * time.Minute)},
		"future":    {body, h, "whsec_s", now.Add(-10 * time.Minute)},
		"malformed": {body, "garbage", "whsec_s", now},
		"bad hex":   {body, "t=1800000000,v1=zz", "whsec_s", now},
	} {
		if VerifySignature(c.body, c.hdr, c.sec, c.at, 5*time.Minute) == nil {
			t.Fatal(name, "must fail")
		}
	}
	rotated := "t=1800000000,v1=00," + strings.SplitN(h, ",", 2)[1]
	if err := VerifySignature(body, rotated, "whsec_s", now, time.Minute); err != nil {
		t.Fatal("any matching v1 must pass", err)
	}
}

func TestCreatePaymentIntent(t *testing.T) {
	var gotAuth, gotIdem, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth, gotIdem = r.Header.Get("Authorization"), r.Header.Get("Idempotency-Key")
		_ = r.ParseForm()
		gotBody = r.PostForm.Encode()
		w.Write([]byte(`{"id":"pi_1","client_secret":"pi_1_secret_x","livemode":false}`))
	}))
	defer srv.Close()
	c := New("sk_test_abc", srv.URL)
	in, err := c.CreatePaymentIntent(context.Background(), 12345, "THB", "card", "idem-1", map[string]string{"intent_id": "pi_tep"})
	if err != nil || in.ID != "pi_1" || in.ClientSecret != "pi_1_secret_x" {
		t.Fatal(in, err)
	}
	if gotAuth == "" || gotIdem != "idem-1" || !strings.Contains(gotBody, "amount=12345") || !strings.Contains(gotBody, "currency=thb") || !strings.Contains(gotBody, "intent_id%5D=pi_tep") {
		t.Fatal(gotAuth, gotIdem, gotBody)
	}
	if _, err := c.CreatePaymentIntent(context.Background(), 0, "THB", "card", "k", nil); err == nil {
		t.Fatal("zero amount")
	}
}

func TestCreatePaymentIntentErrors(t *testing.T) {
	for name, body := range map[string]struct {
		code int
		js   string
	}{
		"api error": {402, `{"error":{"message":"card declined"}}`},
		"live mode": {200, `{"id":"pi_1","client_secret":"s","livemode":true}`},
		"malformed": {200, `{}`},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(body.code)
			w.Write([]byte(body.js))
		}))
		if _, err := New("sk_test_abc", srv.URL).CreatePaymentIntent(context.Background(), 100, "thb", "card", "k", nil); err == nil {
			t.Fatal(name, "must error")
		}
		srv.Close()
	}
	if _, err := New("sk_test_abc", "http://127.0.0.1:1").CreatePaymentIntent(context.Background(), 100, "thb", "card", "k", nil); err == nil {
		t.Fatal("network error must surface")
	}
}
