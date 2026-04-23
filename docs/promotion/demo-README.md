# ShuLing demo.tape — rendering guide

This directory contains `demo.tape`, a [vhs](https://github.com/charmbracelet/vhs) script that renders a ~75-second terminal GIF showing the ShuLing v2.3.0 flow end-to-end: preflight → `帮我发小红书` → topic pick → outline → image generation → publish → SQLite record.

The whole script is self-contained. It does **not** require a real ShuLing install, a real Gemini API key, or a real Xiaohongshu account — all "agent output" is simulated with `printf` / `echo` so the GIF can be produced on any machine, including CI.

## Install vhs

```bash
# macOS
brew install vhs

# Linux (Debian/Ubuntu)
# See https://github.com/charmbracelet/vhs#installation for the current package
# or install via Go:
go install github.com/charmbracelet/vhs@latest

# Verify
vhs --version
```

vhs depends on `ttyd` and `ffmpeg`. On macOS with Homebrew these pull in automatically. On Linux make sure both are on `PATH`.

## Render the GIF

```bash
cd /root/shuling-promotion   # or wherever demo.tape lives
vhs demo.tape
# -> writes demo.gif alongside the tape file (~800x600, ~75s)
```

A successful render prints something like:

```
Creating ...
Host  ... http://127.0.0.1:<port>
Output demo.gif
Done.
```

## Tuning

Everything below is an easy knob inside `demo.tape`:

| You want to... | Edit this |
|---|---|
| Make the whole recording shorter | Reduce `Sleep` durations in each section (`Sleep 3s` → `Sleep 1500ms`) |
| Make typing feel faster/slower | `Set TypingSpeed 50ms` at the top, or the per-call `Type@80ms` rate |
| Change the color theme | `Set Theme "Dracula"` → `"Monokai"`, `"Catppuccin Mocha"`, `"GitHub"`, etc. |
| Change the canvas | `Set Width 800` / `Set Height 600` |
| Change the font | `Set FontSize 14`, plus `Set FontFamily "JetBrains Mono"` if installed |
| Skip a section | Wrap the block in `Hide` ... `Show` **(remove its `Show`)** or just delete the block |
| Record as MP4 instead | Change `Output demo.gif` to `Output demo.mp4` |
| Get a smaller file | After render: `gifsicle -O3 --lossy=80 demo.gif -o demo-small.gif` |

## Section map

Each numbered section in `demo.tape` has a `# ====` banner so you can jump to it quickly:

1. Repo layout (`ls`, `tree`)
2. Preflight check (`bash install.sh --check`, 7 green rows)
3. Claude Code launch + typed prompt `帮我发小红书`
4. 3-option topic selection (high / medium / ε-greedy exploration)
5. User types `1`
6. Outline generation (6 pages, scrolled progressively)
7. Image generation (6 progress bars, Gemini 3 Pro, reference=P1)
8. Publish success + `note_id` + URL
9. SQLite record preview (`sqlite3 ... select ...`)

## Why simulated output?

vhs can only record whatever a real shell does. Invoking the real Claude CLI inside a recording is non-deterministic (network latency, model output variance, auth prompts, token costs) and would produce a different GIF every run. The tape uses `printf` / `cat` to replay a canonical "happy path" transcript, which is what a landing-page demo should show. If you later want a *real* recording, comment out the simulated `printf` lines and drop in `Type "claude"` with a pre-seeded prompt.

## Troubleshooting

- **"ttyd: command not found"** — install via `brew install ttyd` (macOS) or follow the [ttyd install docs](https://github.com/tsl0922/ttyd#installation).
- **Chinese characters render as tofu boxes** — install a CJK-capable monospace font (e.g. `Sarasa Mono SC`, `LXGW WenKai Mono`) and add `Set FontFamily "Sarasa Mono SC"` near the top of the tape.
- **GIF is too big to upload to GitHub (>10 MB)** — run `gifsicle -O3 --lossy=80 demo.gif -o demo.gif` to re-compress, or switch `Output` to `demo.mp4` and upload a video instead.
- **Output looks sped up / frames dropped** — lower `Set PlaybackSpeed 1.0` to `0.9` and re-render.
