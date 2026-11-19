package main

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestSpeechSettings(t *testing.T) {
	const mode = `"flutter.neura.tts.reply_speech_mode.v1":`
	const legacy = `"flutter.neura.tts.speak_replies":`
	const level = `"flutter.neura.tts.volume":`
	cases := []struct {
		name, before, mode, level string
	}{
		{"new", "{}", "afterComplete", ""},
		{"empty object with whitespace", " { \n } \r\n", "afterComplete", ""},
		{"saved off", "{" + mode + `"off"}`, "afterComplete", ""},
		{"legacy mute", "{" + legacy + "false}", "afterComplete", ""},
		{"legacy streamed", "{" + legacy + "true}", "streamed", ""},
		{"saved off has priority", "{" + mode + `"off",` + legacy + "true}", "afterComplete", ""},
		{"stream preference", "{" + mode + `"streamed",` + level + "0.39}", "streamed", "0.39"},
		{"muted volume", "{" + level + "0.0}", "afterComplete", "0.7"},
		{"integer volume", "{" + level + "1}", "afterComplete", "1.0"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out, err := enableReplies([]byte(c.before))
			if err != nil {
				t.Fatal(err)
			}
			var values map[string]json.RawMessage
			if err := json.Unmarshal(out, &values); err != nil {
				t.Fatal(err)
			}
			if string(values[replyMode]) != `"`+c.mode+`"` ||
				string(values[legacyOn]) != "true" || string(values[volume]) != c.level {
				t.Fatalf("wrong speaker settings in %s", out)
			}
			if len(values) != 2 && !(len(values) == 3 && c.level != "") {
				t.Fatalf("unexpected preference in %s", out)
			}
			again, err := enableReplies(out)
			if err != nil || !bytes.Equal(again, out) {
				t.Fatal("second launch changed the settings")
			}
		})
	}
}

func TestUnrelatedPreferencesRemainVerbatim(t *testing.T) {
	const unrelated = `"flutter.test.number":9223372036854775807, "flutter.test.items" : [ "x\u0026y", 1.0, {"Case":"A", "case":"b"} ], "flutter.neura.voice.on_startup.v1":false`
	before := []byte(`{"flutter.neura.tts.volume":0.0, ` + unrelated + ` , "flutter.neura.tts.reply_speech_mode.v1" : "off" }`)
	out, err := enableReplies(before)
	if err != nil || !json.Valid(out) || !bytes.Contains(out, []byte(unrelated)) {
		t.Fatal("an unrelated value or its representation changed")
	}
}

func TestRejectUnreadablePreferences(t *testing.T) {
	for _, value := range []string{"", "null", "[]", "{", "{}{}", `{"flutter.neura.tts.volume":0,"flutter.neura.tts.volume":1}`} {
		if _, err := enableReplies([]byte(value)); err == nil {
			t.Fatalf("accepted invalid fixture %q", value)
		}
	}
}
