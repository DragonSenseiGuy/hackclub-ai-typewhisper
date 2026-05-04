# Hack Club AI plugin for TypeWhisper

A [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) plugin that uses [Hack Club AI](https://ai.hackclub.com) for both LLM post-processing and dictation.

- **Chat / LLM**: free, no API key. Calls `POST https://ai.hackclub.com/chat/completions` (OpenAI-compatible). Active model is auto-discovered from `GET https://ai.hackclub.com/model`.
- **Transcription**: routes audio through Hack Club's Replicate proxy (`POST https://ai.hackclub.com/replicate/predictions`) running `openai/whisper`. Requires a [Replicate](https://replicate.com) API token, stored in the macOS Keychain.

## Install (from a release)

1. Grab the latest `HackClubAIPlugin-vX.Y.Z.zip` from the [Releases page](https://github.com/DragonSenseiGuy/hackclub-ai-typewhisper/releases).
2. Unzip it — you'll get `HackClubAIPlugin.bundle`.
3. Drop the bundle into TypeWhisper's plugin directory and restart TypeWhisper:

   ```bash
   mkdir -p "$HOME/Library/Application Support/TypeWhisper/Plugins"
   mv HackClubAIPlugin.bundle "$HOME/Library/Application Support/TypeWhisper/Plugins/"
   ```

4. In TypeWhisper:
   1. Settings → Plugins → enable **Hack Club AI**.
   2. Settings → LLM → choose **Hack Club AI** (no key needed).
   3. Settings → Transcription → choose **Hack Club AI**, paste a Replicate token in the plugin settings, click **Save token** then **Test connection**.

## Build locally (macOS 14+, Swift 6 / Xcode 16)

```bash
swift build -c release --arch arm64 --arch x86_64
```

SwiftPM emits `lib HackClubAIPlugin.dylib` per arch. To wrap it into the `.bundle` TypeWhisper expects, mirror what CI does in `.github/workflows/release.yml` (lipo the dylibs, then assemble `HackClubAIPlugin.bundle/Contents/{MacOS,Resources,Info.plist}`).

## Cutting a release

CI lives in [`.github/workflows/release.yml`](.github/workflows/release.yml). It runs on `macos-15` with Xcode 16, builds a universal binary, wraps it in `HackClubAIPlugin.bundle`, zips it with `ditto`, and publishes the zip + SHA-256 to a GitHub Release.

Two ways to trigger it:

**A. Push a semver tag (preferred):**

```bash
git checkout main && git pull
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

The `push: tags - 'v*.*.*'` trigger fires automatically and creates / updates the matching release.

**B. Manual dispatch:**

GitHub → **Actions** → **Build & Release** → **Run workflow** → enter a tag like `v0.1.0` → **Run workflow**. The workflow creates the tag and release if they don't already exist.

After it succeeds, the Release page hosts:

- `HackClubAIPlugin-vX.Y.Z.zip`  — the plugin bundle, universal (arm64 + x86_64)
- `HackClubAIPlugin-vX.Y.Z.zip.sha256` — checksum for verification

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
