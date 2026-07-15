# Deck Writeup Images — Securing External Image Loading

## Context

Deck writeups (`decks.description_md`, imported verbatim from MarvelCDB) frequently
embed images via Markdown (`![](https://…)`) or raw `<img>`. Authors paste URLs
from arbitrary third-party hosts — `static0.cbrimages.com`, `www.syfy.com`,
`static0.srcdn.com`, image CDNs, personal blogs, etc. The set of hosts is
open-ended and not knowable ahead of time.

These are rendered by `Sanctum.Decks.Writeup` (MDEx → sanitized HTML) inside the
`.deck-writeup` block on `DeckLive.Show`.

## Current state (interim)

To make images render, `img-src` in
`SanctumWeb.Plugs.ContentSecurityPolicy` was widened to include `https:`:

```
img-src 'self' blob: data: https: https://marvelcdb.com https://<bucket>;
```

This works, but it is a **blunt, app-wide relaxation** and should be treated as
temporary.

## Why the interim solution is not "proper"

1. **Privacy / tracking leakage.** Every embedded image is a live request from the
   viewer's browser to a third party. That host learns the viewer's IP address,
   User-Agent, and (via `Referer`) that they viewed this deck. A malicious or
   ad-tech author can embed a 1×1 tracking pixel and silently log everyone who
   opens the deck. `https:` in `img-src` authorizes all of this.
2. **App-wide blast radius.** The relaxation is global (it's one CSP for the whole
   `:browser` pipeline), so it loosens the policy on *every* page, not just deck
   detail — even though only deck writeups need it.
3. **Reliability / rot.** Hotlinked images break when the third party moves, hot-link
   -blocks, or disappears. The deck page's appearance depends on servers we don't
   control.
4. **Mixed-content & integrity.** We render whatever bytes the host returns today,
   which may differ from what the author intended (or be swapped for something
   hostile later). No integrity pinning is possible.

## Proposed proper solution: mirror writeup images to our bucket

Mirror external writeup images into the existing public Tigris bucket
(`sanctum-cards`, config key `:card_image_base_url`) — the same approach already
used for card scans in `Sanctum.CardImages` — and rewrite the writeup's `src` to
point at the bucket. Then **revert the CSP**: with images served from a host
already in `img-src`, `https:` can be dropped and the policy returns to a tight
allowlist.

### Why this is better

- CSP goes back to an explicit host allowlist (`'self'`, bucket, marvelcdb) — no
  blanket `https:`.
- Zero third-party requests from viewers' browsers → no IP/UA leakage, no tracking
  pixels.
- Images are stable and self-hosted; deck pages stop depending on foreign uptime.
- Reuses proven infrastructure (`CardImages.mirror/2`, sigv4 upload, public URL).

### Design

**1. Extraction & mirroring at import time (not render time).**
Do the work once, in the deck sync path (`Sanctum.Decks.DecklistSyncWorker` /
`Sanctum.DeckSync`), not on every page view. Render-time mirroring would put a
network round-trip on the request path and re-fetch on every view.

- Parse `description_md` for image URLs (Markdown `![](url)` and raw `<img src>`).
- For each external URL, compute a stable object key, e.g.
  `writeups/<sha256(url)>.<ext>` (content-addressed by source URL; dedupes repeats
  and shared images across decks).
- Reuse the `CardImages` download/upload machinery, generalized:
  - `download/1` already handles `http`-prefixed absolute URLs and retries.
  - `upload/2` already does sigv4 PUT to the bucket.
  - Extract a shared `Sanctum.ObjectStore` (or add `CardImages.mirror_url/2`) so
    both card scans and writeup images share one code path.
- Store a mapping from original URL → bucket URL. Options:
  - **(a) Rewrite in place:** store a derived `description_html` (or a
    `description_md` with rewritten `src`) on the deck at sync time. Render reads
    the pre-rewritten field. Simplest read path.
  - **(b) Lookup table:** a `writeup_images` resource (`source_url`, `object_key`,
    `mirrored_at`, `status`) that `Writeup` consults at render time to swap URLs.
    Keeps the original markdown pristine; better if we want to re-mirror or audit.
  - Recommendation: **(a)** for simplicity, keeping the raw `description_md`
    untouched and adding a rendered/rewritten cache column, regenerated on sync.

**2. Fetch safety (SSRF & abuse hardening).**
Since we now fetch arbitrary author-supplied URLs server-side, guard the fetch:

- Allow only `http`/`https` schemes.
- Resolve the host and **reject private/loopback/link-local ranges** (block SSRF to
  `169.254.169.254`, `127.0.0.1`, `10.0.0.0/8`, etc.).
- Cap response size (e.g. 5 MB) and enforce a fetch timeout.
- Validate `Content-Type` is an image and re-encode/normalize if we want to be
  strict (e.g. pipe through an image lib to strip EXIF/polyglot payloads).
- Set our existing descriptive `User-Agent`; do not forward viewer identity.

**3. Background & failure handling.**
- Run mirroring in an Oban job (per deck, or a batch worker), so a slow/dead host
  never blocks import.
- On fetch failure, leave the original URL (or a placeholder) and record the
  failure; retry on next sync. Never fail the whole deck import over one image.

**4. Revert the CSP.**
Once writeup images are served from the bucket, remove `https:` from `img-src` in
`SanctumWeb.Plugs.ContentSecurityPolicy` (both dev and prod branches). Verify no
remaining page relies on external images.

### Migration

1. Ship the mirroring worker; backfill existing decks (`mix` task or one-off Oban
   enqueue over all decks with images).
2. Confirm rewritten writeups render from the bucket.
3. Drop `https:` from the CSP; re-verify deck pages.

## Alternative: on-the-fly image proxy

Instead of mirroring, route images through an app endpoint
(`/img-proxy?url=…`) that fetches, validates, caches, and re-serves them from
`'self'`. Keeps CSP tight without bucket writes.

- Pros: no storage growth for one-off images; images still self-served.
- Cons: same SSRF hardening required; adds a live-fetch path (needs caching to
  avoid hammering origins); signing the `url` param is needed to prevent the proxy
  being used as an open relay. More moving parts than mirroring for our use case.

Mirroring is preferred because the infrastructure already exists and writeup images
are effectively static once imported.

## Recommendation

Adopt **mirror-to-bucket at import time** with SSRF-hardened fetching, then revert
the CSP `https:` relaxation. Treat the current `https:` allowance as a documented,
temporary measure until that lands.
