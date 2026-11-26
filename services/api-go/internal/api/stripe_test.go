package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Bas-travel/tep/services/api-go/internal/config"
	"github.com/Bas-travel/tep/services/api-go/internal/stripe"
)

const stripeWH = "whsec_test_0123456789"

func (e *env) stripeEvent(id, typ string, amount int64, intentID string, live bool, goodSig bool) (int, map[string]any) {
	raw, _ := json.Marshal(map[string]any{"id": id, "type": typ, "livemode": live, "data": map[string]any{"object": map[string]any{
		"amount": amount, "currency": "thb", "metadata": map[string]string{"intent_id": intentID}}}})
	secret := stripeWH
	if !goodSig {
		secret = "whsec_wrong"
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/payments/stripe", strings.NewReader(string(raw)))
	req.Header.Set("Stripe-Signature", stripe.Sign(raw, secret, e.now))
	rec := httptest.NewRecorder()
	e.s.Handler().ServeHTTP(rec, req)
	var m map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &m)
	return rec.Code, m
}

func TestStripeSandboxFlow(t *testing.T) {
	var calls atomic.Int32
	var lastIdem, lastForm string
	psp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		lastIdem = r.Header.Get("Idempotency-Key")
		_ = r.ParseForm()
		lastForm = r.PostForm.Encode()
		w.Write([]byte(`{"id":"pi_sandbox","client_secret":"pi_sandbox_secret_abc","livemode":false}`))
	}))
	defer psp.Close()
	e := newEnvCfg(t, nil, func(c *config.Config) {
		c.MockPayment, c.StripeSecretKey, c.StripeWebhookSecret, c.StripeAPIBase = true, "sk_test_abc", stripeWH, psp.URL
	})
	tk := e.login()
	_, b, _ := e.do("POST", "/v1/bookings", tk, map[string]any{"lines": []any{map[string]any{"listingId": 6, "quantity": 1}}})
	code, pi, _ := e.do("POST", "/v1/payments/intents", tk, map[string]any{"bookingId": b["id"], "method": "card"}, "Idempotency-Key", "k-1")
	if code != 201 || pi["clientSecret"] != "pi_sandbox_secret_abc" || pi["status"] != "pending" {
		t.Fatal(code, pi)
	}
	id, amount := pi["id"].(string), satang(pi["amount"].(float64))
	if lastIdem != id || !strings.Contains(lastForm, "currency=thb") || calls.Load() != 1 {
		t.Fatal(lastIdem, lastForm, calls.Load())
	}
	// replay with the same Idempotency-Key must not call Stripe again
	if code, _, _ := e.do("POST", "/v1/payments/intents", tk, map[string]any{"bookingId": b["id"], "method": "card"}, "Idempotency-Key", "k-1"); code != 201 || calls.Load() != 1 {
		t.Fatal("idempotent replay hit Stripe", code, calls.Load())
	}
	// MOCK_PAYMENT auto-settle must be off while Stripe is active
	e.now = e.now.Add(time.Minute)
	status := func() string {
		_, m, _ := e.do("GET", "/v1/bookings/"+itoa(b["id"].(float64)), tk, nil)
		return m["status"].(string)
	}
	if status() != "pending_payment" {
		t.Fatal("mock auto-settle ran with Stripe enabled")
	}
	if c, _ := e.stripeEvent("evt_1", "payment_intent.succeeded", amount, id, false, false); c != 401 {
		t.Fatal("bad signature", c)
	}
	if c, _ := e.stripeEvent("evt_2", "payment_intent.succeeded", amount, id, true, true); c != 422 {
		t.Fatal("live event", c)
	}
	if c, _ := e.stripeEvent("evt_3", "payment_intent.succeeded", amount-1, id, false, true); c != 422 {
		t.Fatal("amount mismatch", c)
	}
	if status() != "pending_payment" {
		t.Fatal("rejected events must not confirm")
	}
	if c, m := e.stripeEvent("evt_4", "charge.refunded", amount, id, false, true); c != 200 || m["ignored"] != true {
		t.Fatal(c, m)
	}
	if c, m := e.stripeEvent("evt_5", "payment_intent.succeeded", amount, id, false, true); c != 200 || m["duplicate"] != false {
		t.Fatal(c, m)
	}
	if status() != "confirmed" {
		t.Fatal("booking not confirmed by Stripe webhook")
	}
	if c, m := e.stripeEvent("evt_5", "payment_intent.succeeded", amount, id, false, true); c != 200 || m["duplicate"] != true {
		t.Fatal("redelivery must be a no-op", c, m)
	}
	if c, _ := e.stripeEvent("evt_6", "payment_intent.succeeded", amount, "pi_unknown", false, true); c != 404 {
		t.Fatal("unknown intent", c)
	}
}

func TestStripeUnavailableAndDisabled(t *testing.T) {
	psp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(500) }))
	defer psp.Close()
	e := newEnvCfg(t, nil, func(c *config.Config) {
		c.StripeSecretKey, c.StripeWebhookSecret, c.StripeAPIBase = "sk_test_abc", stripeWH, psp.URL
	})
	tk := e.login()
	_, b, _ := e.do("POST", "/v1/bookings", tk, map[string]any{"lines": []any{map[string]any{"listingId": 6}}})
	if code, _, _ := e.do("POST", "/v1/payments/intents", tk, map[string]any{"bookingId": b["id"], "method": "promptpay"}); code != 502 {
		t.Fatal("PSP failure must be 502", code)
	}
	if code, _, _ := e.do("POST", "/v1/payments/intents", tk, map[string]any{"bookingId": b["id"], "method": "wallet"}); code == 502 {
		t.Fatal("wallet must not depend on the PSP")
	}
	off := newEnv(t, nil)
	if c, _ := off.stripeEvent("evt_x", "payment_intent.succeeded", 100, "x", false, true); c != 404 {
		t.Fatal("stripe webhook must be 404 when disabled", c)
	}
}
