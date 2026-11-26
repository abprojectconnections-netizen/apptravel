package api

import "testing"

func TestLogoutRevokesRefreshToken(t *testing.T) {
	e := newEnv(t, nil)
	_, tok, _ := e.do("POST", "/v1/auth/login", "", map[string]string{"email": "demo@tep.dev", "password": "Passw0rd!"})
	at, rt := tok["accessToken"].(string), tok["refreshToken"].(string)
	if code, _, _ := e.do("POST", "/v1/auth/logout", at, map[string]string{}); code != 422 {
		t.Fatal("empty refresh token must be 422", code)
	}
	if code, _, _ := e.do("POST", "/v1/auth/logout", at, map[string]string{"refreshToken": rt}); code != 204 {
		t.Fatal("logout", code)
	}
	if code, _, _ := e.do("POST", "/v1/auth/refresh", "", map[string]string{"refreshToken": rt}); code != 401 {
		t.Fatal("revoked token must not refresh", code)
	}
}

func TestStaffAndAdminDetailEndpoints(t *testing.T) {
	e := newEnv(t, nil)
	st, ad, demo := e.loginAs("staff@tep.dev"), e.loginAs("admin@tep.dev"), e.login()

	_, m, _ := e.do("GET", "/admin/v1/partners", ad, nil)
	items := pitems(m)
	if len(items) == 0 {
		t.Fatal("no partners")
	}
	pid := itoa(items[0].(map[string]any)["id"].(float64))
	if code, m, _ := e.do("GET", "/admin/v1/partners/"+pid, ad, nil); code != 200 || m["id"] == nil {
		t.Fatal(code, m)
	}
	if code, _, _ := e.do("GET", "/admin/v1/partners/999999", ad, nil); code != 404 {
		t.Fatal(code)
	}
	if code, _, _ := e.do("GET", "/admin/v1/partners/abc", ad, nil); code != 404 {
		t.Fatal(code)
	}
	if code, _, _ := e.do("GET", "/admin/v1/partners/"+pid, st, nil); code != 403 {
		t.Fatal("staff must not read admin partner", code)
	}

	if code, m, _ := e.do("GET", "/staff/v1/bookings/1", st, nil); code != 200 || m["id"] == nil {
		t.Fatal(code, m)
	}
	for _, p := range []string{"/staff/v1/bookings/999999", "/staff/v1/bookings/x", "/staff/v1/tickets/999999", "/staff/v1/tickets/x"} {
		if code, _, _ := e.do("GET", p, st, nil); code != 404 {
			t.Fatal(p, code)
		}
	}
	code, m, _ := e.do("POST", "/v1/support/tickets", demo, map[string]any{"subject": "ทดสอบ", "message": "รายละเอียด"})
	if code != 201 {
		t.Fatal(code, m)
	}
	tid := itoa(m["id"].(float64))
	if code, m, _ := e.do("GET", "/staff/v1/tickets/"+tid, st, nil); code != 200 || m["subject"] != "ทดสอบ" {
		t.Fatal(code, m)
	}
	if code, _, _ := e.do("GET", "/staff/v1/tickets/"+tid, demo, nil); code != 403 {
		t.Fatal("traveler must not read staff ticket", code)
	}
}
