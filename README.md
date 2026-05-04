# Hack Club AI plugin for TypeWhisper

A [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) plugin that uses [Hack Club AI](https://ai.hackclub.com) for both LLM post-processing and dictation.

- **Chat / LLM**: free, no API key. Calls `POST https://ai.hackclub.com/chat/completions` (OpenAI-compatible). Active model is auto-discovered from `GET https://ai.hackclub.com/model`.
- **Transcription**: routes audio through Hack Club's Replicate proxy (`POST https://ai.hackclub.com/replicate/predictions`) running `openai/whisper`. Requires a [Replicate](https://replicate.com) API token, stored in the macOS Keychain.

## Build

```bash
swift build -c release
```

This produces `.build/release/HackClubAIPlugin.bundle`. Confirm `Contents/Resources/manifest.json` is present in the bundle.

## Install

Copy the bundle into TypeWhisper's plugin directory and restart TypeWhisper:

```bash
mkdir -p "$HOME/Library/Application Support/TypeWhisper/Plugins"
cp -R .build/release/HackClubAIPlugin.bundle "$HOME/Library/Application Support/TypeWhisper/Plugins/"
```

In TypeWhisper:
1. Settings → Plugins → enable **Hack Club AI**.
2. Settings → LLM → choose **Hack Club AI** (no key needed).
3. Settings → Transcription → choose **Hack Club AI**, paste a Replicate token in the plugin settings, click **Save token** then **Test connection**.

## Endpoint sanity check

```bash
curl https://ai.hackclub.com/model
curl -X POST https://ai.hackclub.com/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hi"}]}'
```

## Layout

```
Package.swift
Resources/manifest.json
Sources/HackClubAIPlugin/
  HackClubAIPlugin.swift        # principalClass; LLM + transcription protocol conformances + settings UI
  HackClubChatClient.swift      # /chat/completions, streaming + non-streaming
  HackClubReplicateClient.swift # /replicate/predictions, polling
```

## License

MIT.
