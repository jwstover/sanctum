## [1.60.1](https://github.com/jwstover/sanctum/compare/v1.60.0...v1.60.1) (2026-07-21)


### Bug Fixes

* **search:** keep mobile search sheet on-screen when keyboard opens ([e152f8c](https://github.com/jwstover/sanctum/commit/e152f8ce01b0e258edb07c9fe47c1cf2917a3e8b))



# [1.60.0](https://github.com/jwstover/sanctum/compare/v1.59.1...v1.60.0) (2026-07-21)


### Bug Fixes

* **filters:** stack filter button below search on mobile, pin sheet footer ([d1e51bb](https://github.com/jwstover/sanctum/commit/d1e51bbcf4f0b45e09c56203856d7f4ee2f87926))


### Features

* **builder:** move deckbuilder card picker filters into the filter sheet ([eb5bf8d](https://github.com/jwstover/sanctum/commit/eb5bf8d6a76c3e506d541fac2f196cdbb84e813b))
* **cards:** replace card pool filter pills with unified filter sheet ([ed4c0a3](https://github.com/jwstover/sanctum/commit/ed4c0a370cc5804c9d12dcb13724b63c43052374))
* **decks:** move deck browser filters into the unified filter sheet ([8f0a038](https://github.com/jwstover/sanctum/commit/8f0a038d8b6630ee04c3b68577020a902bd729dc))
* **filters:** typeahead vocabulary inputs + aligned, separated sections ([4504b86](https://github.com/jwstover/sanctum/commit/4504b868fb016e4b6bdf643bf0ee18db927f273b))
* **search:** add FormSync/FormSchema for two-way filter form sync ([7990779](https://github.com/jwstover/sanctum/commit/7990779202ac54bea1633d4a231efd12b40d328c))



## [1.59.1](https://github.com/jwstover/sanctum/compare/v1.59.0...v1.59.1) (2026-07-21)


### Bug Fixes

* **cards:** render printed X values instead of -1 and make search X-aware ([995f32f](https://github.com/jwstover/sanctum/commit/995f32f561074fef96f9e435a715c97359d82e07))



# [1.59.0](https://github.com/jwstover/sanctum/compare/v1.58.0...v1.59.0) (2026-07-21)


### Features

* **decks:** extend hover card previews to decklists ([0c2f84b](https://github.com/jwstover/sanctum/commit/0c2f84baf3bf22299ab750727d45aecc1b052a95))
* **ui:** render timestamps in the browser's timezone ([57212eb](https://github.com/jwstover/sanctum/commit/57212eb07ca3f13605e7c69e6815cb38ed3ad636))



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



