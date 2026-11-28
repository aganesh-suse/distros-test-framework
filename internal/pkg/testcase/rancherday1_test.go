package testcase

import "testing"

func TestWebhookRolledOut(t *testing.T) {
	for status, want := range map[string]bool{
		"3/3 1/1/1": true,
		"2/3 1/1/1": false, // new spec not observed yet
		"3/3 0/1/1": false, // old pod still serving
		"3/3 1/0/1": false, // new pod not ready
		"3/3 //1":   false, // jsonpath leaves empty fields while the pod starts
		"":          false,
		"1/1 0/0/0": false, // scaled to zero serves nothing
	} {
		if got := webhookRolledOut(status); got != want {
			t.Errorf("webhookRolledOut(%q) = %v, want %v", status, got, want)
		}
	}
}
