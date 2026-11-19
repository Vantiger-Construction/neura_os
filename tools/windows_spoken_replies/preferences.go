package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

const (
	replyMode = "flutter.neura.tts.reply_speech_mode.v1"
	legacyOn  = "flutter.neura.tts.speak_replies"
	volume    = "flutter.neura.tts.volume"
)

type field struct {
	key        string
	start, end int
}

// Rewrite only the values of Neura's speaker settings. Keep every unrelated
// value, including integer precision, whitespace and string escapes, verbatim.
func enableReplies(data []byte) ([]byte, error) {
	invalid := errors.New("Neura's settings could not be read safely")
	if !json.Valid(data) {
		return nil, invalid
	}
	reader := json.NewDecoder(bytes.NewReader(data))
	token, err := reader.Token()
	if err != nil || token != json.Delim('{') {
		return nil, invalid
	}
	values := make(map[string]json.RawMessage, 3)
	var fields []field
	count := 0
	for reader.More() {
		keyToken, err := reader.Token()
		if err != nil {
			return nil, invalid
		}
		key := keyToken.(string)
		var raw json.RawMessage
		if err := reader.Decode(&raw); err != nil {
			return nil, invalid
		}
		count++
		if key == replyMode || key == legacyOn || key == volume {
			if _, duplicate := values[key]; duplicate {
				return nil, invalid
			}
			values[key] = raw
			end := int(reader.InputOffset())
			fields = append(fields, field{key, end - len(raw), end})
		}
	}

	var savedMode string
	_ = json.Unmarshal(values[replyMode], &savedMode)
	changes := make(map[string]string, 3)
	if savedMode != "afterComplete" && savedMode != "streamed" {
		changes[replyMode] = `"afterComplete"`
		if values[replyMode] == nil && string(values[legacyOn]) == "true" {
			changes[replyMode] = `"streamed"`
		}
	}
	if string(values[legacyOn]) != "true" {
		changes[legacyOn] = "true"
	}
	// A missing volume uses Neura's normal default. Keep an audible setting
	// that the user chose. Dart getDouble requires a floating-point JSON value.
	if raw := values[volume]; raw != nil {
		literal := string(raw)
		level, err := strconv.ParseFloat(literal, 64)
		switch {
		case err != nil || level <= 0 || level > 1:
			changes[volume] = "0.7"
		case !strings.ContainsAny(literal, ".eE"):
			changes[volume] = literal + ".0"
		}
	}

	if len(changes) == 0 {
		return data, nil
	}
	var out bytes.Buffer
	offset := 0
	for _, f := range fields {
		if replacement, ok := changes[f.key]; ok {
			out.Write(data[offset:f.start])
			out.WriteString(replacement)
			offset = f.end
			delete(changes, f.key)
		}
	}
	insertAt := int(reader.InputOffset())
	out.Write(data[offset:insertAt])
	for _, key := range []string{replyMode, legacyOn} {
		if replacement, ok := changes[key]; ok {
			if count > 0 {
				out.WriteByte(',')
			}
			out.WriteString(strconv.Quote(key))
			out.WriteByte(':')
			out.WriteString(replacement)
			count++
		}
	}
	out.Write(data[insertAt:])
	return out.Bytes(), nil
}
