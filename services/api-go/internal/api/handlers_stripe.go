package api

import (
	"context"
	"encoding/json"
	"io"
	"math"
	"net/http"
	"time"

	"github.com/Bas-travel/tep/services/api-go/internal/httpx"
	"github.com/Bas-travel/tep/services/api-go/internal/stripe"
)

// errPSPUnavailable maps a failed PSP call to 502 so the client can retry with the same Idempotency-Key.
var errPSPUnavailable = &apiErr{Status: 502, Code: "PSP_UNAVAILABLE", Title: "Bad Gateway", Detail: "payment provider is unavailable, please retry"}

const stripeCurrency = "thb"

func satang(amount float64) int64 { return int64(math.Round(amount * 100)) }

// stripeCreate creates a TEST-MODE Stripe PaymentIntent for a card/PromptPay intent. The TEP intent id travels in
// metadata and is the Stripe Idempotency-Key, so webhooks map back to the booking and retries cannot double-charge.
func (s *Server) stripeCreate(ctx context.Context, pi *intentRec) error {
	in, err := s.stripe.CreatePaymentIntent(ctx, satang(pi.Amount), stripeCurrency, pi.Method, pi.ID, map[string]string{
		"intent_id": pi.ID, "booking_id": itoa64(pi.BookingID),
	})
	if err != nil {
		return err
	}
	pi.ClientSecret = in.ClientSecret
	return nil
}

// stripeWebhook authenticates a Stripe event (Stripe-Signature, 5-minute tolerance), de-duplicates by event id and
// applies payment_intent.succeeded / payment_intent.payment_failed. The amount must match the stored intent.
func (s *Server) stripeWebhook(w http.ResponseWriter, r *http.Request) {
	if s.stripe == nil {
		httpx.NotFound(w, r)
		return
	}
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
	if err != nil {
		httpx.Invalid(w, r, fe("body", "unreadable"))
		return
	}
	if err := stripe.VerifySignature(raw, r.Header.Get("Stripe-Signature"), s.cfg.StripeWebhookSecret, s.now(), 5*time.Minute); err != nil {
		httpx.Unauthorized(w, r, "invalid signature")
		return
	}
	var ev struct {
		ID       string `json:"id"`
		Type     string `json:"type"`
		Livemode bool   `json:"livemode"`
		Data     struct {
			Object struct {
				Amount   int64             `json:"amount"`
				Currency string            `json:"currency"`
				Metadata map[string]string `json:"metadata"`
			} `json:"object"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &ev); err != nil || ev.ID == "" || len(ev.ID) > 120 {
		httpx.Invalid(w, r, fe("body", "invalid stripe event"))
		return
	}
	if ev.Livemode {
		httpx.Invalid(w, r, fe("livemode", "live-mode events are not accepted"))
		return
	}
	status := map[string]string{"payment_intent.succeeded": "succeeded", "payment_intent.payment_failed": "failed"}[ev.Type]
	intentID := ev.Data.Object.Metadata["intent_id"]
	if status == "" || intentID == "" {
		httpx.WriteJSON(w, 200, map[string]any{"received": true, "ignored": true}) // other event types: acknowledge only
		return
	}
	duplicate := false
	err = s.repo.Tx(r.Context(), func(tx Tx) error {
		if e := tx.AddWebhookEvent("stripe", ev.ID, s.now()); e != nil {
			if e == ErrDuplicate {
				duplicate = true
				return nil
			}
			return e
		}
		pi, e := tx.GetIntent(intentID, true)
		if e != nil {
			return e
		}
		if status == "succeeded" && (ev.Data.Object.Amount != satang(pi.Amount) || ev.Data.Object.Currency != stripeCurrency) {
			return invalid(fe("amount", "does not match the stored payment intent"))
		}
		return s.finishIntent(tx, pi, status)
	})
	if s.fail(w, r, err) {
		return
	}
	httpx.WriteJSON(w, 200, map[string]any{"received": true, "duplicate": duplicate})
}
