# [1.58.0](https://github.com/jwstover/sanctum/compare/v1.57.0...v1.58.0) (2026-07-21)


### Bug Fixes

* **decks:** aspect-ratio card tiles + qty badges on fresh mounts ([de3ced7](https://github.com/jwstover/sanctum/commit/de3ced7153e56ebaad36ba0084797a37663df2d9))
* **decks:** dedicated pips column in the panel list view ([54627b5](https://github.com/jwstover/sanctum/commit/54627b56fb90e9d47d2eaee894e6dac777d81b92))
* **decks:** right-align resource pips on locked hero rows ([c9e3271](https://github.com/jwstover/sanctum/commit/c9e3271b61e56a503b7bcfb08372342e7ad57b98))
* **ui:** drop the z-10 stacking cap on the app layout main ([7b90f19](https://github.com/jwstover/sanctum/commit/7b90f19aec5d994c9b841707226eac481a53fe89))


### Features

* **decks:** #card autocomplete in the description editor ([81d1e2c](https://github.com/jwstover/sanctum/commit/81d1e2c166f41c38dc46542dacc69be5337789a6))
* **decks:** $icon picker + [token] glyph rendering in writeups ([2a4c999](https://github.com/jwstover/sanctum/commit/2a4c99923eb79d706694c1a1b7dbfd620ce39cca))
* **decks:** 44px mobile steppers + haptic feedback + drag-to-dismiss pane ([d76e4bf](https://github.com/jwstover/sanctum/commit/d76e4bff0cc7a3024efb30dfbbe4c7d39800e841))
* **decks:** advisory deck legality module ([c99e5fb](https://github.com/jwstover/sanctum/commit/c99e5fb16df16dcbf2218e6603e8b08b1b78cc8f))
* **decks:** arrow-key navigation in the writeup picker overlay ([fb3bdbf](https://github.com/jwstover/sanctum/commit/fb3bdbf2dc998f2fa12e347a23a2f14e05f2a1d6))
* **decks:** builder grid with tap-to-add steppers + staples quick-add ([bae6543](https://github.com/jwstover/sanctum/commit/bae6543bcb95b9554b3882f27901b8cfb92818e4))
* **decks:** deck panel — desktop side column + mobile slide-up pane ([f6623cd](https://github.com/jwstover/sanctum/commit/f6623cd0adfa0d98fd6e040d385a3755c17f483e))
* **decks:** formatting toolbar + card/icon picker overlay in the editor ([ccad3c8](https://github.com/jwstover/sanctum/commit/ccad3c89375f1da803fd256c1eaa1cb5731b5b21))
* **decks:** hero picker at /decks/new + builder route ([91847b4](https://github.com/jwstover/sanctum/commit/91847b47767082b459dc4ae18b24236eabb5d2e4))
* **decks:** hover card preview popover for writeup card links ([aace70f](https://github.com/jwstover/sanctum/commit/aace70ffefc836da670ae983e3f89372332575b0))
* **decks:** move deck delete into the builder header ([a3ca86e](https://github.com/jwstover/sanctum/commit/a3ca86e85fec595ec5ed09c6a80427181f1b0bec))
* **decks:** native deck build action, quantity upsert, owner policies ([077e0bc](https://github.com/jwstover/sanctum/commit/077e0bcc676ef379022475f85ed9a25d48991542))
* **decks:** New Deck + Mine filter on the browser, Edit Deck on detail ([fd9602f](https://github.com/jwstover/sanctum/commit/fd9602fb7ca4e010d7c962efb224d65e804b7df8))
* **decks:** prominent mobile deck bar + scrim behind the slide-up pane ([3ff0a9b](https://github.com/jwstover/sanctum/commit/3ff0a9b6d10e92fd16262300e90ae1f8ce273d09))
* **decks:** tabbed description editor with markdown preview in the builder ([0170803](https://github.com/jwstover/sanctum/commit/0170803d32d2938e8abe0d4890e6cf096f3c0a1b))


### Performance Improvements

* **decks:** fix 69s card: search filter in the deck browser ([7477c6a](https://github.com/jwstover/sanctum/commit/7477c6add13904b97ae9e1415e3b5ba26150dced))



# [1.57.0](https://github.com/jwstover/sanctum/compare/v1.56.0...v1.57.0) (2026-07-21)


### Bug Fixes

* **search:** mobile sheet scroll lock, fixed height, safe-area padding ([a45776e](https://github.com/jwstover/sanctum/commit/a45776eb15ef002795c1574d554d3a23921f53cb))
* **search:** play the sheet slide-up once per open, not per patch ([b6e6154](https://github.com/jwstover/sanctum/commit/b6e6154b31079d6a395ca8e0a7a15e98d46dc921))
* **search:** release the body lock on navigation; 350ms results debounce ([4e20dbf](https://github.com/jwstover/sanctum/commit/4e20dbf93c6c6b76e725828d1d02e57111472949))
* **search:** stop mutating LiveView-managed ids on result rows ([54e02fb](https://github.com/jwstover/sanctum/commit/54e02fbc3cf4b0ce01c76c584e98556759b125f7))


### Features

* **browse:** set-section anchors — /browse/:pack#<set_code> ([3522de0](https://github.com/jwstover/sanctum/commit/3522de00674715ec9981270ce35197bf0f8c3339))
* **search:** cross-type global search core ([c414104](https://github.com/jwstover/sanctum/commit/c41410470d847e2eab1dd949f4808bc454ed7b34))
* **ui:** site-wide search bar in the app header ([ed61c3a](https://github.com/jwstover/sanctum/commit/ed61c3aa21768fee45bc2d5c709f3980c0a82349))



# [1.56.0](https://github.com/jwstover/sanctum/compare/v1.55.0...v1.56.0) (2026-07-20)


### Features

* **collections:** add Collections domain with pack + card ownership resources ([0fd871c](https://github.com/jwstover/sanctum/commit/0fd871c7da4ad4b1d398cd03969930494ee43fe6))
* **collections:** collection indicators + owned summary on deck view ([90917bb](https://github.com/jwstover/sanctum/commit/90917bbab3b818a7e007814e5f8fdd7e1023d8cf))
* **collections:** derived ownership calcs + toggle/remove/lookup API ([b8e2ef7](https://github.com/jwstover/sanctum/commit/b8e2ef77d538e463e0b68d2f0d52ca49e8380f3d))
* **collections:** full pack checklist on the profile ([6bdbbb5](https://github.com/jwstover/sanctum/commit/6bdbbb5404a92decf6200601661a8da265be4758))
* **collections:** order the profile checklist by release wave ([7aae99f](https://github.com/jwstover/sanctum/commit/7aae99f57ccaab7d29ae7d18a29a7f03a19688a4))
* **collections:** owned chip + toggles on card detail and pool ([5b09334](https://github.com/jwstover/sanctum/commit/5b0933458f673495f5e2910d1b1bd074a94b3714))
* **collections:** pack + per-card collection controls on browse pages ([5954f77](https://github.com/jwstover/sanctum/commit/5954f774ad7151f8efe3b4219a2f79b9c6f06862))
* **collections:** populate CardAlt.pack_id in sync + release backfill ([cf27117](https://github.com/jwstover/sanctum/commit/cf27117cd779182e1847b3d241806d92be20b8f4))
* **collections:** private collection section on the profile ([5804d80](https://github.com/jwstover/sanctum/commit/5804d80b109e7643bcdea61dc981fe6dcca6d90f))
* **search:** owned:true/false field filtering by the actor's collection ([629ae9f](https://github.com/jwstover/sanctum/commit/629ae9fdee6a62bc0e2039874cf23de184951458))



# [1.55.0](https://github.com/jwstover/sanctum/compare/v1.54.0...v1.55.0) (2026-07-20)


### Features

* **ui:** pin profile/admin drawer links to bottom with icons ([e6c56b9](https://github.com/jwstover/sanctum/commit/e6c56b9b0358090ec3dc6b9e354e4176b4ec7878))



# [1.54.0](https://github.com/jwstover/sanctum/compare/v1.53.0...v1.54.0) (2026-07-19)


### Features

* **stats:** add public deck stats page with ECharts ([1b502db](https://github.com/jwstover/sanctum/commit/1b502db1759c10288c9b222dfa231bff80ad02a8))
* **stats:** colored KPI tiles and hero→aspect→cards drill-down ([57c8928](https://github.com/jwstover/sanctum/commit/57c89287c5dd2208c1e95edb14d6d269954dca3a))
* **stats:** rename tile label to "Decks Added this Month" ([7ae7a9a](https://github.com/jwstover/sanctum/commit/7ae7a9a1b2c134dd896ac18abefd0ff3bc174dc6))
* **stats:** show all heroes in hero chart, colored per hero ([42ddef8](https://github.com/jwstover/sanctum/commit/42ddef859ae6e4a93e0e07d9a7aaa57beb2550e3))
* **stats:** URL-driven drill state, card links, donut, release markers ([0fb17a9](https://github.com/jwstover/sanctum/commit/0fb17a9e6456a11574c8c4a9361a335cb595903d))



