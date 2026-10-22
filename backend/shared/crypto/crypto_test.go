package crypto

import (
	"context"
	"testing"
)

func TestCryptoRoundtrip(t *testing.T) {
	ctx := context.Background()
	plain := "AB123456C" // Sample National Insurance Number

	enc, err := Encrypt(ctx, plain)
	if err != nil {
		t.Fatalf("Encrypt error: %v", err)
	}
	if enc == plain {
		t.Fatalf("Ciphertext matches plaintext!")
	}

	dec, err := Decrypt(ctx, enc)
	if err != nil {
		t.Fatalf("Decrypt error: %v", err)
	}
	if dec != plain {
		t.Fatalf("Got %q, want %q", dec, plain)
	}
}
