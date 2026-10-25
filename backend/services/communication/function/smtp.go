package function

import (
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/smtp"
	"os"
	"strings"
	"time"
)

// errNoSMTPTransport is returned when no SMTP credentials are configured.
// The caller downgrades to a logged, recorded skip rather than a retry loop:
// a platform without mail configured should keep working, it should just not
// pretend it mailed anyone.
var errNoSMTPTransport = errors.New("SMTP is not configured")

type mailConfig struct {
	host string
	port string
	user string
	pass string
	from string
	name string
}

// mailConfigFromEnv reads the SMTP settings documented in
// backend/PRODUCTION_SETUP.md. Nothing is hardcoded: credentials come from
// the function's environment (Secret Manager / Cloud Run env vars), never
// from this repository.
func mailConfigFromEnv() (mailConfig, error) {
	cfg := mailConfig{
		host: strings.TrimSpace(os.Getenv("SMTP_HOST")),
		port: strings.TrimSpace(os.Getenv("SMTP_PORT")),
		user: os.Getenv("SMTP_USER"),
		pass: os.Getenv("SMTP_PASS"),
		from: strings.TrimSpace(os.Getenv("SMTP_FROM")),
		name: strings.TrimSpace(os.Getenv("SMTP_FROM_NAME")),
	}
	if cfg.host == "" {
		return cfg, errNoSMTPTransport
	}
	if cfg.port == "" {
		cfg.port = "587"
	}
	if cfg.from == "" {
		cfg.from = cfg.user
	}
	if cfg.name == "" {
		cfg.name = "K Flex"
	}
	if cfg.from == "" {
		return cfg, errNoSMTPTransport
	}
	return cfg, nil
}

// sendMail delivers one multipart/alternative message (text + HTML) over
// SMTP, with STARTTLS on submission ports and implicit TLS on 465.
func sendMail(cfg mailConfig, toEmail, subject, htmlBody, textBody string) error {
	msg := buildMIME(cfg, toEmail, subject, htmlBody, textBody)

	var conn net.Conn
	var err error
	addr := net.JoinHostPort(cfg.host, cfg.port)
	if cfg.port == "465" {
		conn, err = tls.Dial("tcp", addr, &tls.Config{ServerName: cfg.host})
	} else {
		conn, err = net.DialTimeout("tcp", addr, 10*time.Second)
	}
	if err != nil {
		return fmt.Errorf("smtp dial: %w", err)
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, cfg.host)
	if err != nil {
		return fmt.Errorf("smtp client: %w", err)
	}
	defer client.Close()

	if cfg.port != "465" {
		if ok, _ := client.Extension("STARTTLS"); ok {
			if err := client.StartTLS(&tls.Config{ServerName: cfg.host}); err != nil {
				return fmt.Errorf("smtp starttls: %w", err)
			}
		}
	}
	if cfg.user != "" {
		auth := smtp.PlainAuth("", cfg.user, cfg.pass, cfg.host)
		if err := client.Auth(auth); err != nil {
			return fmt.Errorf("smtp auth: %w", err)
		}
	}
	if err := client.Mail(cfg.from); err != nil {
		return fmt.Errorf("smtp mail from: %w", err)
	}
	if err := client.Rcpt(toEmail); err != nil {
		return fmt.Errorf("smtp rcpt to: %w", err)
	}
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp data: %w", err)
	}
	if _, err := w.Write(msg); err != nil {
		return fmt.Errorf("smtp write: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("smtp close: %w", err)
	}
	return client.Quit()
}

// buildMIME assembles the RFC 5322 message. Plain text goes first so a
// client that cannot render HTML still shows something sensible.
func buildMIME(cfg mailConfig, toEmail, subject, htmlBody, textBody string) []byte {
	boundary := "kflex-" + fmt.Sprintf("%d", time.Now().UnixNano())
	var b strings.Builder
	writeHeader := func(k, v string) {
		// Header folding keeps long subjects on one encoded line; subjects are
		// ASCII in every template we ship, so plain values are safe.
		fmt.Fprintf(&b, "%s: %s\r\n", k, v)
	}
	writeHeader("From", fmt.Sprintf("%s <%s>", cfg.name, cfg.from))
	writeHeader("To", toEmail)
	writeHeader("Subject", subject)
	writeHeader("Date", time.Now().Format(time.RFC1123Z))
	writeHeader("MIME-Version", "1.0")
	writeHeader("Content-Type", fmt.Sprintf("multipart/alternative; boundary=%q", boundary))
	b.WriteString("\r\n")

	fmt.Fprintf(&b, "--%s\r\n", boundary)
	writeHeader("Content-Type", "text/plain; charset=utf-8")
	writeHeader("Content-Transfer-Encoding", "8bit")
	b.WriteString("\r\n" + textBody + "\r\n")

	fmt.Fprintf(&b, "--%s\r\n", boundary)
	writeHeader("Content-Type", "text/html; charset=utf-8")
	writeHeader("Content-Transfer-Encoding", "8bit")
	b.WriteString("\r\n" + htmlBody + "\r\n")

	fmt.Fprintf(&b, "--%s--\r\n", boundary)
	return []byte(b.String())
}
