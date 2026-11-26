package config

import (
	"strings"
	"testing"
)

func valid() Config {
	return Config{AppEnv: "dev", APIMode: "mock", JWTSecret: PlaceholderJWTSecret, MockPayment: true}
}

func TestDevDefaultsValid(t *testing.T) {
	if err := valid().Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestPlaceholderSecretRejectedOutsideDev(t *testing.T) {
	c := valid()
	c.AppEnv = "beta"
	if c.Validate() == nil {
		t.Fatal("expected error for placeholder secret in beta")
	}
}

func TestProductionRules(t *testing.T) {
	c := Config{AppEnv: "production", APIMode: "db", JWTSecret: "0123456789abcdef0123456789abcdef", MockPayment: true, MySQLDSN: "u:p@tcp(h)/db"}
	if c.Validate() == nil {
		t.Fatal("expected errors: mock payment + no TLS")
	}
	c.MockPayment = false
	c.MySQLDSN += "?tls=true"
	if c.Validate() == nil {
		t.Fatal("expected error: real payments need WEBHOOK_SECRET")
	}
	c.WebhookSecret = "0123456789abcdef0123456789abcdef"
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestDBModeNeedsDSN(t *testing.T) {
	c := valid()
	c.APIMode = "db"
	if c.Validate() == nil {
		t.Fatal("expected error: API_MODE=db without MYSQL_DSN")
	}
}

func TestWebhookSecretRules(t *testing.T) {
	c := valid()
	c.WebhookSecret = "short"
	if c.Validate() == nil {
		t.Fatal("expected error: secret shorter than 32")
	}
	c = valid()
	c.AppEnv, c.JWTSecret, c.WebhookSecret = "beta", "0123456789abcdef0123456789abcdef", PlaceholderWebhookSecret
	if c.Validate() == nil {
		t.Fatal("expected error: placeholder webhook secret outside dev")
	}
}

func TestShortSecret(t *testing.T) {
	c := valid()
	c.JWTSecret = "short"
	if c.Validate() == nil {
		t.Fatal("expected error")
	}
}

func TestTemplatePlaceholderIsRejectedWithHint(t *testing.T) {
	c := valid()
	c.JWTSecret = "__GENERATE__"
	err := c.Validate()
	if err == nil || !strings.Contains(err.Error(), "setup-env") {
		t.Fatalf("expected hint to run setup-env, got %v", err)
	}
}

func TestStripeKeysAreTestModeOnly(t *testing.T) {
	c := valid()
	c.StripeSecretKey, c.StripeWebhookSecret = "sk_live_abc", "whsec_x"
	if c.Validate() == nil {
		t.Fatal("live key must be rejected")
	}
	c.StripeSecretKey, c.StripeWebhookSecret = "sk_test_abc", ""
	if c.Validate() == nil {
		t.Fatal("webhook secret required with a key")
	}
	c.StripeWebhookSecret = "whsec_x"
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}
}
