// Package stripe is a minimal, dependency-free Stripe client for SANDBOX (test mode) payments:
// PaymentIntent creation and webhook signature verification. Live keys are rejected by design.
package stripe

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const DefaultBaseURL = "https://api.stripe.com"

// ValidateKeys enforces test-mode only. Empty key means "Stripe disabled".
func ValidateKeys(secretKey, webhookSecret string) error {
	if secretKey == "" {
		return nil
	}
	if !strings.HasPrefix(secretKey, "sk_test_") {
		return errors.New("STRIPE_SECRET_KEY must be a test-mode key (sk_test_...); live keys are disabled until production is explicitly authorised")
	}
	if !strings.HasPrefix(webhookSecret, "whsec_") {
		return errors.New("STRIPE_WEBHOOK_SECRET (whsec_...) is required when STRIPE_SECRET_KEY is set")
	}
	return nil
}

type Client struct {
	key, base string
	http      *http.Client
}

func New(secretKey, baseURL string) *Client {
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	return &Client{key: secretKey, base: strings.TrimRight(baseURL, "/"), http: &http.Client{Timeout: 15 * time.Second}}
}

type Intent struct {
	ID           string
	ClientSecret string
}

// CreatePaymentIntent creates a PaymentIntent. amount is in the smallest currency unit (satang for THB).
// idemKey makes retries safe (Stripe Idempotency-Key).
func (c *Client) CreatePaymentIntent(ctx context.Context, amount int64, currency, method, idemKey string, meta map[string]string) (Intent, error) {
	if amount <= 0 {
		return Intent{}, errors.New("stripe: amount must be positive")
	}
	f := url.Values{}
	f.Set("amount", strconv.FormatInt(amount, 10))
	f.Set("currency", strings.ToLower(currency))
	f.Add("payment_method_types[]", method)
	for k, v := range meta {
		f.Set("metadata["+k+"]", v)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/v1/payment_intents", strings.NewReader(f.Encode()))
	if err != nil {
		return Intent{}, err
	}
	req.SetBasicAuth(c.key, "")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Idempotency-Key", idemKey)
	resp, err := c.http.Do(req)
	if err != nil {
		return Intent{}, fmt.Errorf("stripe: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	var out struct {
		ID           string `json:"id"`
		ClientSecret string `json:"client_secret"`
		Livemode     bool   `json:"livemode"`
		Error        struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	_ = json.Unmarshal(raw, &out)
	if resp.StatusCode/100 != 2 {
		return Intent{}, fmt.Errorf("stripe: status %d: %s", resp.StatusCode, out.Error.Message)
	}
	if out.Livemode {
		return Intent{}, errors.New("stripe: refusing live-mode object")
	}
	if out.ID == "" || out.ClientSecret == "" {
		return Intent{}, errors.New("stripe: malformed response")
	}
	return Intent{ID: out.ID, ClientSecret: out.ClientSecret}, nil
}

// VerifySignature checks a Stripe-Signature header ("t=...,v1=...") over "<t>.<payload>" with HMAC-SHA256.
// Any v1 may match (secret rotation); timestamps older/newer than tolerance are rejected (replay protection).
func VerifySignature(payload []byte, header, secret string, now time.Time, tolerance time.Duration) error {
	var ts int64
	var sigs []string
	for _, part := range strings.Split(header, ",") {
		k, v, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok {
			continue
		}
		switch k {
		case "t":
			ts, _ = strconv.ParseInt(v, 10, 64)
		case "v1":
			sigs = append(sigs, v)
		}
	}
	if ts == 0 || len(sigs) == 0 {
		return errors.New("malformed signature header")
	}
	if d := now.Sub(time.Unix(ts, 0)); d > tolerance || d < -tolerance {
		return errors.New("timestamp outside tolerance")
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(strconv.FormatInt(ts, 10) + "."))
	mac.Write(payload)
	want := mac.Sum(nil)
	for _, s := range sigs {
		if got, err := hex.DecodeString(s); err == nil && hmac.Equal(got, want) {
			return nil
		}
	}
	return errors.New("signature mismatch")
}

// Sign builds a valid header for tests and local tooling.
func Sign(payload []byte, secret string, at time.Time) string {
	mac := hmac.New(sha256.New, []byte(secret))
	ts := strconv.FormatInt(at.Unix(), 10)
	mac.Write([]byte(ts + "."))
	mac.Write(payload)
	return "t=" + ts + ",v1=" + hex.EncodeToString(mac.Sum(nil))
}
