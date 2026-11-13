package function

import (
	"fmt"
	"regexp"
	"strings"
)

// This file renders the small Markdown subset the operations console offers
// when an administrator writes an email. It is deliberately hand-written
// rather than pulling in a Markdown library: the console needs a predictable,
// safe subset for email (headings, emphasis, links, images, lists, quotes,
// rules, code), and every one of those is a dozen lines here.
//
// The ordering matters and is the whole safety story: the source is HTML-
// escaped FIRST, and only then are the Markdown markers turned into tags. An
// administrator pasting "<script>" therefore lands in the message as text,
// exactly like the plain-text composer in paragraphsToHTML.

var (
	// Ordered alternation: images before links, so "![alt](src)" is not
	// half-matched as a link with a leading "!".
	reInlineImage = regexp.MustCompile(`!\[([^\]]*)\]\(([^)\s]+)\)`)
	reInlineLink  = regexp.MustCompile(`\[([^\]]+)\]\(([^)\s]+)\)`)

	reBold       = regexp.MustCompile(`\*\*([^*]+)\*\*`)
	reBoldUnder  = regexp.MustCompile(`__([^_]+)__`)
	reItalic     = regexp.MustCompile(`\*([^*\n]+)\*`)
	reItalicUnd  = regexp.MustCompile(`_([^_\n]+)_`)
	reStrike     = regexp.MustCompile(`~~([^~]+)~~`)
	reCodeSpan   = regexp.MustCompile("`([^`]+)`")
	reOrderedItem = regexp.MustCompile(`^(\d+)[.)]\s+(.*)$`)
)

const (
	styleH    = "margin:0 0 12px; font-size:%dpx; line-height:1.3; color:#0F172A; font-weight:700;"
	styleP    = "margin:0 0 14px; font-size:15px; line-height:1.6; color:#1E293B;"
	styleMuted = "color:#64748B;"
)

// RenderMarkdown converts the console's Markdown subset into email-safe HTML.
// Output is a sequence of block elements with inline styles (email clients
// strip <style> blocks, so nothing here depends on a stylesheet).
func RenderMarkdown(source string) string {
	lines := strings.Split(strings.ReplaceAll(source, "\r\n", "\n"), "\n")
	var out strings.Builder
	i := 0

	for i < len(lines) {
		trimmed := strings.TrimSpace(lines[i])

		if trimmed == "" {
			i++
			continue
		}

		// Fenced code block.
		if strings.HasPrefix(trimmed, "```") {
			i++
			var code []string
			for i < len(lines) && !strings.HasPrefix(strings.TrimSpace(lines[i]), "```") {
				code = append(code, lines[i])
				i++
			}
			i++ // closing fence
			out.WriteString(`<pre style="margin:0 0 14px; padding:12px 14px; background:#F1F5F9; border-radius:8px; font-size:13px; line-height:1.5; color:#0F172A; overflow:auto;"><code>` +
				escape(strings.Join(code, "\n")) + `</code></pre>`)
			continue
		}

		// Horizontal rule.
		if trimmed == "---" || trimmed == "***" || trimmed == "___" {
			out.WriteString(`<hr style="border:none; border-top:1px solid #E2E8F0; margin:22px 0;">`)
			i++
			continue
		}

		// Heading.
		if level, text, ok := markdownHeading(trimmed); ok {
			out.WriteString(fmt.Sprintf(`<h%d style="`+styleH+`">%s</h%d>`, level, headingSize(level), inlineMarkdown(text), level))
			i++
			continue
		}

		// Block quote.
		if strings.HasPrefix(trimmed, ">") {
			var quoted []string
			for i < len(lines) && strings.HasPrefix(strings.TrimSpace(lines[i]), ">") {
				quoted = append(quoted, strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(lines[i]), ">")))
				i++
			}
			out.WriteString(`<blockquote style="margin:0 0 14px; padding:10px 16px; border-left:3px solid #CBD5E1; color:#475569; font-size:14px; line-height:1.6;">` +
				inlineMarkdown(strings.Join(quoted, "\n")) + `</blockquote>`)
			continue
		}

		// Lists (consecutive items only; nesting is flattened rather than
		// silently mangled).
		if _, _, ok := markdownBullet(trimmed); ok {
			var items []string
			for i < len(lines) {
				text, _, isBullet := markdownBullet(strings.TrimSpace(lines[i]))
				if !isBullet {
					break
				}
				items = append(items, text)
				i++
			}
			out.WriteString(`<ul style="margin:0 0 14px; padding-left:20px; font-size:15px; line-height:1.6; color:#1E293B;">`)
			for _, item := range items {
				out.WriteString("<li style=\"margin:0 0 6px;\">" + inlineMarkdown(item) + "</li>")
			}
			out.WriteString(`</ul>`)
			continue
		}
		if match := reOrderedItem.FindStringSubmatch(trimmed); match != nil {
			var items []string
			start := match[1]
			for i < len(lines) {
				m := reOrderedItem.FindStringSubmatch(strings.TrimSpace(lines[i]))
				if m == nil {
					break
				}
				items = append(items, m[2])
				i++
			}
			out.WriteString(`<ol start="` + escape(start) + `" style="margin:0 0 14px; padding-left:22px; font-size:15px; line-height:1.6; color:#1E293B;">`)
			for _, item := range items {
				out.WriteString("<li style=\"margin:0 0 6px;\">" + inlineMarkdown(item) + "</li>")
			}
			out.WriteString(`</ol>`)
			continue
		}

		// Paragraph: consume until a blank line or the start of another block.
		var para []string
		for i < len(lines) {
			line := strings.TrimSpace(lines[i])
			if line == "" || startsBlock(line) {
				break
			}
			para = append(para, line)
			i++
		}
		if len(para) > 0 {
			out.WriteString(`<p style="` + styleP + `">` + inlineMarkdown(strings.Join(para, "\n")) + `</p>`)
		}
	}

	return out.String()
}

// PlainTextFromMarkdown strips the markup for the text/plain alternative, so
// a client that cannot render HTML still reads the message and, importantly,
// still sees where a link points.
func PlainTextFromMarkdown(source string) string {
	lines := strings.Split(strings.ReplaceAll(source, "\r\n", "\n"), "\n")
	var out []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			if len(out) > 0 && out[len(out)-1] != "" {
				out = append(out, "")
			}
			continue
		}
		if trimmed == "---" || trimmed == "***" || trimmed == "___" {
			out = append(out, "----------------------------------------")
			continue
		}
		if level, text, ok := markdownHeading(trimmed); ok && level >= 1 {
			out = append(out, strings.ToUpper(plainInline(text)), "")
			continue
		}
		if strings.HasPrefix(trimmed, "```") {
			continue
		}
		if text, ordered, isBullet := markdownBullet(trimmed); isBullet {
			bullet := "• "
			if ordered {
				bullet = "- "
			}
			out = append(out, bullet+plainInline(text))
			continue
		}
		if match := reOrderedItem.FindStringSubmatch(trimmed); match != nil {
			out = append(out, match[1]+". "+plainInline(match[2]))
			continue
		}
		if strings.HasPrefix(trimmed, ">") {
			out = append(out, "> "+plainInline(strings.TrimSpace(strings.TrimPrefix(trimmed, ">"))))
			continue
		}
		out = append(out, plainInline(trimmed))
	}
	return strings.TrimRight(strings.Join(out, "\n"), "\n")
}

func startsBlock(line string) bool {
	if strings.HasPrefix(line, "```") || strings.HasPrefix(line, ">") {
		return true
	}
	if _, _, ok := markdownHeading(line); ok {
		return true
	}
	if _, _, ok := markdownBullet(line); ok {
		return true
	}
	if reOrderedItem.MatchString(line) {
		return true
	}
	return line == "---" || line == "***" || line == "___"
}

func markdownHeading(line string) (int, string, bool) {
	level := 0
	for level < len(line) && line[level] == '#' {
		level++
	}
	if level == 0 || level > 6 || level >= len(line) || line[level] != ' ' {
		return 0, "", false
	}
	return level, strings.TrimSpace(line[level:]), true
}

func headingSize(level int) int {
	switch level {
	case 1:
		return 24
	case 2:
		return 20
	case 3:
		return 17
	default:
		return 15
	}
}

// markdownBullet matches "- item", "* item" and "+ item".
func markdownBullet(line string) (string, bool, bool) {
	for _, marker := range []string{"- ", "* ", "+ "} {
		if strings.HasPrefix(line, marker) {
			return strings.TrimSpace(line[len(marker):]), false, true
		}
	}
	return "", false, false
}

// inlineMarkdown handles one line-or-paragraph's inline markup. The input is
// escaped before any tag is introduced, and link/image targets are checked
// against an allow-list of schemes, so neither a pasted tag nor a
// "javascript:" URL can get through.
func inlineMarkdown(text string) string {
	// Code spans are pulled out first: their content must not be treated as
	// bold/italic/link markup.
	var codeSpans []string
	text = reCodeSpan.ReplaceAllStringFunc(text, func(match string) string {
		inner := strings.TrimSuffix(strings.TrimPrefix(match, "`"), "`")
		codeSpans = append(codeSpans, `<code style="background:#F1F5F9; padding:1px 5px; border-radius:4px; font-size:13px; color:#0F172A;">`+escape(inner)+`</code>`)
		return fmt.Sprintf("\x00code%d\x00", len(codeSpans)-1)
	})

	text = escape(text)

	text = reInlineImage.ReplaceAllStringFunc(text, func(match string) string {
		parts := reInlineImage.FindStringSubmatch(match)
		src := strings.TrimSpace(parts[2])
		if !safeEmailURL(src) {
			return parts[1]
		}
		style := "max-width:100%; height:auto; border-radius:10px; display:block; margin:0 0 8px;"
		return fmt.Sprintf(`<img src="%s" alt="%s" style="%s">`, src, parts[1], style)
	})
	text = reInlineLink.ReplaceAllStringFunc(text, func(match string) string {
		parts := reInlineLink.FindStringSubmatch(match)
		href := strings.TrimSpace(parts[2])
		label := parts[1]
		if !safeEmailURL(href) {
			return label
		}
		return fmt.Sprintf(`<a href="%s" style="color:#2563EB; text-decoration:underline; font-weight:600;">%s</a>`, href, label)
	})

	text = reBold.ReplaceAllString(text, `<strong style="font-weight:700;">$1</strong>`)
	text = reBoldUnder.ReplaceAllString(text, `<strong style="font-weight:700;">$1</strong>`)
	text = reStrike.ReplaceAllString(text, `<span style="text-decoration:line-through;">$1</span>`)
	text = reItalic.ReplaceAllString(text, `<em>$1</em>`)
	text = reItalicUnd.ReplaceAllString(text, `<em>$1</em>`)

	text = strings.ReplaceAll(text, "\n", "<br>")

	for i, span := range codeSpans {
		text = strings.Replace(text, fmt.Sprintf("\x00code%d\x00", i), span, 1)
	}
	return text
}

func plainInline(text string) string {
	text = reInlineImage.ReplaceAllString(text, "$1 ($2)")
	text = reInlineLink.ReplaceAllString(text, "$1 ($2)")
	text = reCodeSpan.ReplaceAllString(text, "$1")
	text = reBold.ReplaceAllString(text, "$1")
	text = reBoldUnder.ReplaceAllString(text, "$1")
	text = reStrike.ReplaceAllString(text, "$1")
	text = reItalic.ReplaceAllString(text, "$1")
	text = reItalicUnd.ReplaceAllString(text, "$1")
	return strings.ReplaceAll(text, "\n", " ")
}

// safeEmailURL accepts absolute http(s) links and mailto:. Anything else —
// javascript:, data:, a relative path with no host — is refused and the
// surrounding text is kept instead.
func safeEmailURL(raw string) bool {
	lower := strings.ToLower(raw)
	for _, prefix := range []string{"http://", "https://", "mailto:"} {
		if strings.HasPrefix(lower, prefix) {
			// "http://" alone, or with a space/quote smuggled in, is not a link.
			return len(raw) > len(prefix)+2 && !strings.ContainsAny(raw, " \"'<>")
		}
	}
	return false
}
