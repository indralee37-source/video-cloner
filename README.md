# video-clone — portable video-ad cloning skill hub

A self-contained, **backend-agnostic** skill package for cloning and reverse-engineering
video ads. Drop it into any repo, fill in one adapter file for your video-generation API,
and the agent can:

- **Clone an existing video ad** → analyze its style, pacing, dialogue, and camera work,
  then generate a *new* video adapted for a different product (`prompting/clone-ad/`).
- **Reverse-engineer a video style** → turn it into a reusable, fill-in-the-blank prompt
  template you can reuse for any product (`prompting/analyze-video/`).
- **Generate from a brief** → straight text/image → video using the prompt library
  (`prompting/prompt-library/`).

It is modeled on the Arcads `arcads-external-api` skill, but every API-specific detail
(endpoints, auth, polling, pricing, model constraints) lives behind a single **adapter
contract** so you can point it at *any* backend — Arcads, fal.ai, Replicate, Runway,
a direct vendor API, or your own service.

## The one idea: the adapter

The skill never calls a concrete API directly. It calls **abstract operations**:

| Operation | Meaning |
|-----------|---------|
| `auth` | how to authenticate |
| `upload(file)` | upload a reference image/video/audio → returns a handle |
| `submit(prompt, params, refs)` | start a generation → returns a job id |
| `poll(id)` | check status → `pending` / `done` / `failed` + output URL |
| `capabilities` | durations, aspect ratios, i2v/v2v/t2v support, audio, pricing |

Your job is to map those operations to your real backend **once**, in
[`adapters/_ADAPTER.template.md`](adapters/_ADAPTER.template.md). A fully worked
example (Arcads + Seedance 2.0) is in
[`adapters/example-arcads-seedance.md`](adapters/example-arcads-seedance.md) so you can
see exactly what "filling it in" looks like.

## Install into a repo

1. Copy this whole folder into your repo, e.g. `skills/video-clone/`.
2. Copy `adapters/_ADAPTER.template.md` → `adapters/active.md` and fill it in for your
   backend. (Until `active.md` exists, the agent will ask you to create it before any
   generation.)
3. Register the skill so your agent can find it:
   - **Claude Code:** put the folder under `.claude/skills/video-clone/` (or symlink), or
     add a project rule pointing at `skills/video-clone/SKILL.md`.
   - Or just tell the agent: *"use the video-clone skill at `<path>/SKILL.md`"*.
4. Install local tooling (frame extraction + transcription):
   ```bash
   brew install ffmpeg            # frame + audio extraction
   brew install yt-dlp            # download reference videos from URLs (YouTube, Instagram, TikTok, …)
   pip3 install openai-whisper    # dialogue transcription (optional but recommended)
   ```

## Layout

```
video-clone/
├── README.md                     ← you are here
├── SKILL.md                      ← router: decision tree + execution checklist
├── reference.md                  ← the adapter CONTRACT + generic video mechanics
├── adapters/
│   ├── _ADAPTER.template.md      ← fill-in-the-blank backend spec → copy to active.md
│   └── example-arcads-seedance.md← worked example (Arcads + Seedance 2.0)
├── prompting/
│   ├── guide.md                  ← marketing brief → prompt playbook
│   ├── clone-ad/
│   │   └── SKILL.md              ← clone a video → GENERATE a new adapted video
│   ├── analyze-video/
│   │   ├── SKILL.md              ← deconstruct a video → reusable TEMPLATE (.md)
│   │   └── scripts/
│   │       └── extract-frames.sh ← ffmpeg frame + audio extraction (portable)
│   └── prompt-library/           ← 8 ready-to-use style formulas + a skeleton
│       ├── _TEMPLATE.md          ← skeleton for a new style template
│       ├── ugc-selfie.md         ← phone-filmed review / testimonial
│       ├── unboxing-hype.md      ← high-energy package → reveal → reaction
│       ├── problem-solution.md   ← before/after direct-response arc
│       ├── testimonial-authority.md ← founder/expert talking head, trust-led
│       ├── feature-walkthrough.md   ← fast-paced feature demo
│       ├── studio-lookbook.md    ← polished multi-look spot w/ voiceover
│       ├── product-hero.md       ← no-person elemental product reveal
│       └── premium-reveal.md     ← no-person dark-void text-narrative drop
└── logs/
    └── README.md                 ← generation log schema (logs/video-clone.jsonl)
```

## Where to start

- Building the backend hookup → [`reference.md`](reference.md) +
  [`adapters/_ADAPTER.template.md`](adapters/_ADAPTER.template.md).
- Understanding the agent's behavior → [`SKILL.md`](SKILL.md).
- Cloning your first ad → [`prompting/clone-ad/SKILL.md`](prompting/clone-ad/SKILL.md).
