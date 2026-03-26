package app

import "strings"

func (a *App) applyConversationCompression(conversationID string, normalized NormalizedInput) (NormalizedInput, string, int) {
	conversationID = strings.TrimSpace(conversationID)
	segments := cloneConversationPromptSegments(normalized.Segments)
	if len(segments) == 0 {
		return normalized, "", 0
	}

	existingSummary := ""
	if conversationID != "" {
		if stored, err := a.State.loadConversationSummary(conversationID); err == nil && stored != nil {
			existingSummary = strings.TrimSpace(stored.SummaryText)
		}
	}

	compressedSegments, summary, coveredCount, changed := compressConversationSegments(existingSummary, segments)
	if changed {
		normalized.Segments = compressedSegments
		normalized.HiddenPrompt = appendSummaryToHiddenPrompt(normalized.HiddenPrompt, summary)
		normalized.Prompt = buildConversationPrompt(compressedSegments, shouldForceTranscriptPrompt(compressedSegments))
		return normalized, summary, coveredCount
	}

	if existingSummary != "" {
		normalized.HiddenPrompt = appendSummaryToHiddenPrompt(normalized.HiddenPrompt, existingSummary)
	}
	return normalized, "", 0
}

func shouldForceTranscriptPrompt(segments []conversationPromptSegment) bool {
	for _, segment := range normalizeConversationHistorySegments(segments) {
		if strings.TrimSpace(strings.ToLower(segment.Role)) != "user" {
			return true
		}
	}
	return false
}
