# Business Requirements Document — Lune
### Native macOS Navidrome Client
**Version:** 1.0  
**Date:** 2026-05-29  
**Status:** Draft

---

## 1. Business Objective

Deliver a free, open-source, native macOS client for the Navidrome self-hosted music server that fills a clear gap in the Navidrome ecosystem and establishes Lune as the reference macOS client for the Subsonic API ecosystem.

---

## 2. Business Context

The self-hosted software market is growing as users seek privacy and ownership over their data. Navidrome has become the dominant self-hosted music server with tens of thousands of active instances. No native macOS client exists. This represents an opportunity to:

1. Serve an underserved user segment with a high-quality tool
2. Build reputation in the open-source community
3. Lay groundwork for a freemium Mac App Store release (future)

---

## 3. Stakeholders

| Stakeholder | Role | Interest |
|---|---|---|
| Developer (Sahil) | Owner / Engineer | Ship a polished product |
| Navidrome community | Primary users | Get a native Mac client |
| macOS ecosystem | Platform | Adoption of Apple APIs |

---

## 4. Business Requirements

### BR-01: Open Source Distribution
The application must be released as open source (MIT or Apache 2.0) to encourage community contribution and adoption by the Navidrome community.

### BR-02: Mac App Store Readiness
The codebase must be structured so a sandboxed Mac App Store build is achievable without a rewrite. All file access must go through App Sandbox-compatible paths, and credentials must use Keychain.

### BR-03: Zero Runtime Cost (v1)
v1.0 must incur no ongoing infrastructure costs. The app communicates directly from client to the user's own Navidrome server — no intermediary backend.

### BR-04: Subsonic API Compatibility
The client must work with any Subsonic-compatible server (Navidrome, Airsonic, Funkwhale with Subsonic plugin), not just Navidrome. This maximizes the addressable user base.

### BR-05: Quality Bar
The application must meet Apple's Human Interface Guidelines and be comparable in quality and feel to first-party Apple apps (Music, Podcasts). A mediocre app damages credibility more than no app.

### BR-06: Community Signals
Success of v1.0 is measured partly by GitHub stars, community forum mentions, and Reddit/HN reception in self-hosting communities.

---

## 5. Assumptions

- Users are technically proficient enough to run their own Navidrome server
- Users have a stable local network connection to their server most of the time
- The Subsonic API is stable enough to build against without major breaking changes

---

## 6. Dependencies

| Dependency | Owner | Risk |
|---|---|---|
| Subsonic API | Navidrome project | Low — stable, versioned |
| AVFoundation | Apple | Low — first-party |
| macOS 14 SDK | Apple | Low |
| Keychain Services | Apple | Low |

---

## 7. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple changes sandbox rules | Low | Follow HIG; build for App Sandbox from day 1 |
| Navidrome API changes | Low | Pin to Subsonic v1.16.1; add version negotiation |
| Scope creep delays v1.0 | Medium | Strict MVP feature list; defer nice-to-haves |

---

## 8. Out of Scope (Business Level)

- Monetization in v1 (no IAP, no subscription)
- Support contracts or SLAs
- Windows or Linux versions
- Hosting any user data
