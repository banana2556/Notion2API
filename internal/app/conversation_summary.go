package app

import (
	"fmt"
	"strings"
	"time"
)

const (
	conversationSummaryRecentSegments   = 6
	conversationSummaryMinSegments      = 10
	conversationSummaryMinChars         = 2200
	conversationSummarySectionLineLimit = 4
	conversationSummaryBulletLimit      = 180
)

type ConversationMemorySummary struct {
	ConversationID      string    `json:"conversation_id"`
	Fingerprint         string    `json:"fingerprint"`
	SummaryText         string    `json:"summary_text"`
	CoveredMessageCount int       `json:"covered_message_count"`
	UpdatedAt           time.Time `json:"updated_at"`
}

func buildConversationMemorySummary(existing string, older []conversationPromptSegment) string {
	existing = normalizeExistingConversationSummary(existing)
	if len(older) == 0 {
		return existing
	}

	userPreferences := make([]string, 0, conversationSummarySectionLineLimit)
	establishedContext := make([]string, 0, conversationSummarySectionLineLimit)
	recentHighlights := make([]string, 0, conversationSummarySectionLineLimit)

	for _, segment := range older {
		role := strings.TrimSpace(strings.ToLower(segment.Role))
		text := summarizeConversationSegment(segment.Text)
		if text == "" {
			continue
		}
		if role == "user" {
			if looksLikePreferenceOrConstraint(text) {
				userPreferences = appendUniqueSummaryLine(userPreferences, text)
				continue
			}
			recentHighlights = appendRollingSummaryLine(recentHighlights, "User asked for "+text)
			continue
		}
		establishedContext = appendRollingSummaryLine(establishedContext, "Assistant established "+text)
	}

	sections := []string{"[Conversation Summary]"}
	if existing != "" {
		sections = append(sections, formatSummarySection("Previously retained memory", splitSummaryLines(existing, conversationSummarySectionLineLimit)))
	}
	if len(establishedContext) > 0 {
		sections = append(sections, formatSummarySection("Established context", establishedContext))
	}
	if len(userPreferences) > 0 {
		sections = append(sections, formatSummarySection("User preferences and constraints", userPreferences))
	}
	if len(recentHighlights) > 0 {
		sections = append(sections, formatSummarySection("Earlier exchange highlights", recentHighlights))
	}
	if len(sections) == 1 {
		return existing
	}
	return strings.TrimSpace(strings.Join(sections, "\n\n"))
}

func shouldCompressConversationSegments(segments []conversationPromptSegment) bool {
	normalized := normalizeConversationHistorySegments(segments)
	if len(normalized) < conversationSummaryMinSegments {
		return false
	}
	total := 0
	for _, segment := range normalized {
		total += len(segment.Text)
	}
	return total >= conversationSummaryMinChars
}

func appendSummaryToHiddenPrompt(hiddenPrompt string, summary string) string {
	summary = strings.TrimSpace(summary)
	if summary == "" {
		return strings.TrimSpace(hiddenPrompt)
	}
	if strings.TrimSpace(hiddenPrompt) == "" {
		return "[Compressed conversation memory]\n" + summary
	}
	return strings.TrimSpace(hiddenPrompt) + "\n\n[Compressed conversation memory]\n" + summary
}

func compressConversationSegments(existingSummary string, segments []conversationPromptSegment) ([]conversationPromptSegment, string, int, bool) {
	normalized := normalizeConversationHistorySegments(segments)
	if !shouldCompressConversationSegments(normalized) {
		return cloneConversationPromptSegments(normalized), strings.TrimSpace(existingSummary), 0, false
	}
	if len(normalized) <= conversationSummaryRecentSegments {
		return cloneConversationPromptSegments(normalized), strings.TrimSpace(existingSummary), 0, false
	}
	covered := len(normalized) - conversationSummaryRecentSegments
	older := cloneConversationPromptSegments(normalized[:covered])
	recent := cloneConversationPromptSegments(normalized[covered:])
	summary := buildConversationMemorySummary(existingSummary, older)
	if strings.TrimSpace(summary) == "" {
		return cloneConversationPromptSegments(normalized), strings.TrimSpace(existingSummary), 0, false
	}
	return recent, summary, covered, true
}

func normalizeExistingConversationSummary(existing string) string {
	existing = strings.TrimSpace(existing)
	if existing == "" {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(existing, "[Conversation Summary]"))
}

func summarizeConversationSegment(text string) string {
	text = collapseWhitespace(text)
	if text == "" {
		return ""
	}
	return truncateRunes(text, conversationSummaryBulletLimit)
}

func splitSummaryLines(text string, limit int) []string {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	lines := strings.Split(text, "\n")
	out := make([]string, 0, minInt(len(lines), limit))
	for _, line := range lines {
		line = strings.TrimSpace(strings.TrimPrefix(line, "-"))
		if line == "" {
			continue
		}
		out = append(out, truncateRunes(collapseWhitespace(line), conversationSummaryBulletLimit))
		if len(out) >= limit {
			break
		}
	}
	return out
}

func appendUniqueSummaryLine(lines []string, value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return lines
	}
	for _, line := range lines {
		if strings.EqualFold(line, value) {
			return lines
		}
	}
	if len(lines) >= conversationSummarySectionLineLimit {
		return lines
	}
	return append(lines, value)
}

func appendRollingSummaryLine(lines []string, value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return lines
	}
	if len(lines) >= conversationSummarySectionLineLimit {
		lines = append([]string{}, lines[len(lines)-conversationSummarySectionLineLimit+1:]...)
	}
	return append(lines, value)
}

func formatSummarySection(title string, lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	parts := make([]string, 0, len(lines)+1)
	parts = append(parts, fmt.Sprintf("%s:", title))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts = append(parts, "- "+line)
	}
	if len(parts) == 1 {
		return ""
	}
	return strings.Join(parts, "\n")
}

func looksLikePreferenceOrConstraint(text string) bool {
	lower := strings.ToLower(strings.TrimSpace(text))
	if lower == "" {
		return false
	}
	keywords := []string{
		"请", "不要", "别", "必须", "需要", "希望", "尽量", "记住", "以后", "始终", "只要", "优先",
		"please", "must", "need", "prefer", "remember", "always", "never", "avoid", "only", "keep", "use ",
	}
	for _, keyword := range keywords {
		if strings.Contains(lower, keyword) {
			return true
		}
	}
	return false
}
