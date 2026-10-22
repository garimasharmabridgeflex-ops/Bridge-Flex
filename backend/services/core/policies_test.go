package function

import (
	"testing"
)

func TestHasUnresolvedPlaceholders(t *testing.T) {
	cases := []struct {
		name     string
		content  string
		expected bool
	}{
		{
			name:     "clean content",
			content:  "This is a legally binding agreement for K Flex Limited.",
			expected: false,
		},
		{
			name:     "contains registered company name placeholder",
			content:  "These terms are between [REGISTERED COMPANY NAME] and the user.",
			expected: true,
		},
		{
			name:     "contains date placeholder",
			content:  "Last Updated: [DATE]",
			expected: true,
		},
		{
			name:     "contains email placeholder",
			content:  "Contact us at [CONTACT EMAIL] for queries.",
			expected: true,
		},
		{
			name:     "contains normal brackets in math or prose",
			content:  "Section 2 [clause b] applies to nurseries.",
			expected: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := hasUnresolvedPlaceholders(tc.content)
			if got != tc.expected {
				t.Errorf("hasUnresolvedPlaceholders(%q) = %v; want %v", tc.content, got, tc.expected)
			}
		})
	}
}
