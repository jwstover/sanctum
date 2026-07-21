// Hover previews for `/cards/:id` links inside the hook element (deck
// writeups). On hover-intent it asks the LiveView for the card
// ("preview_card"), which renders a card tile into #card-link-preview; this
// hook only positions and toggles that popover. Hover-only devices get the
// feature; touch devices fall through to the normal link navigation.
const SHOW_DELAY_MS = 150;
const MARGIN = 8;

const CardLinkPreview = {
  mounted() {
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return;

    this.timer = null;
    // Card id currently rendered in the popover — re-hovers skip the server.
    this.currentId = null;
    this.anchor = null;

    this.onOver = (e) => {
      const link = e.target.closest('a[href^="/cards/"]');
      if (!link || !this.el.contains(link) || link === this.anchor) return;
      const id = link.getAttribute("href").split("/")[2];
      if (!id) return;
      this.anchor = link;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.request(id, link), SHOW_DELAY_MS);
    };

    this.onOut = (e) => {
      const link = e.target.closest('a[href^="/cards/"]');
      if (!link || link.contains(e.relatedTarget)) return;
      if (link === this.anchor) this.hide();
    };

    this.onHide = () => this.hide();

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
    this.el.addEventListener("click", this.onHide);
    window.addEventListener("scroll", this.onHide, {passive: true, capture: true});
  },

  destroyed() {
    clearTimeout(this.timer);
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    this.el.removeEventListener("click", this.onHide);
    window.removeEventListener("scroll", this.onHide, {capture: true});
  },

  popover() {
    return document.getElementById("card-link-preview");
  },

  request(id, link) {
    if (id === this.currentId) return this.show(link);

    this.pushEvent("preview_card", {id}, (reply) => {
      // Stale replies (mouse moved on, or an unresolvable id) are dropped.
      if (reply.error || this.anchor !== link) return;
      this.currentId = id;
      // The tile patch lands with the reply; wait a frame so we measure it.
      requestAnimationFrame(() => this.anchor === link && this.show(link));
    });
  },

  // Below the link when it fits, above otherwise, clamped to the viewport.
  // Unhide → measure → position happens synchronously, so nothing flashes.
  show(link) {
    const pop = this.popover();
    if (!pop) return;
    pop.classList.remove("hidden");
    const rect = link.getBoundingClientRect();
    const popRect = pop.getBoundingClientRect();

    const left = Math.max(
      MARGIN,
      Math.min(rect.left, window.innerWidth - popRect.width - MARGIN)
    );
    let top = rect.bottom + MARGIN;
    if (top + popRect.height > window.innerHeight - MARGIN) {
      top = Math.max(MARGIN, rect.top - popRect.height - MARGIN);
    }

    pop.style.left = `${left}px`;
    pop.style.top = `${top}px`;
  },

  hide() {
    clearTimeout(this.timer);
    this.anchor = null;
    this.popover()?.classList.add("hidden");
  },
};

export default CardLinkPreview;
