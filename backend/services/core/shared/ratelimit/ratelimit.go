package ratelimit

import (
	"sync"
	"time"
)

// Limiter implements a simple sliding window per-UID rate limiter.
type Limiter struct {
	mu      sync.Mutex
	history map[string][]time.Time
	window  time.Duration
	limit   int
}

// NewLimiter creates a rate limiter allowing at most limit requests per window duration.
func NewLimiter(window time.Duration, limit int) *Limiter {
	return &Limiter{
		history: make(map[string][]time.Time),
		window:  window,
		limit:   limit,
	}
}

// Allow checks whether an action by the given uid is within the rate limit.
func (l *Limiter) Allow(uid string) bool {
	if uid == "" {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-l.window)

	timestamps := l.history[uid]
	valid := timestamps[:0]
	for _, t := range timestamps {
		if t.After(cutoff) {
			valid = append(valid, t)
		}
	}

	if len(valid) >= l.limit {
		l.history[uid] = valid
		return false
	}

	l.history[uid] = append(valid, now)
	return true
}
