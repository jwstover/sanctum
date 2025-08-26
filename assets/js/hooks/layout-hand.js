const LayoutHand = {
  mounted() {
    this.layoutCards();

    // Re-layout on window resize
    this.resizeHandler = () => this.layoutCards();
    window.addEventListener("resize", this.resizeHandler);
  },

  updated() {
    // Re-layout when cards are added/removed
    console.log("layout");
    this.layoutCards();
  },

  destroyed() {
    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler);
    }
  },

  layoutCards() {
    const cards = this.el.querySelectorAll(".game-card");
    const containerWidth = this.el.offsetWidth;
    const containerHeight = this.el.offsetHeight;
    const cardCount = cards.length;

    if (cardCount === 0) return;

    // Get actual card dimensions from first card
    const firstCard = cards[0];

    const img = firstCard.querySelector("img");

    if (!img.complete) {
      setTimeout(() => this.layoutCards(), 100);
    } else {
      const cardWidth = firstCard.offsetWidth;
      const cardHeight = firstCard.offsetHeight;

      console.log(cardWidth);

      // Fan configuration
      const maxFanAngle = 30; // degrees total spread
      const overlapRatio = 0.65; // how much cards overlap (0.65 = 65% overlap)
      const fanRadius = cardHeight * 1.8; // radius of the fan arc

      // Calculate the angle step between cards
      const angleStep = cardCount > 1 ? maxFanAngle / (cardCount - 1) : 0;
      const startAngle = -maxFanAngle / 2;

      // Calculate spacing based on available width and card overlap
      const availableWidth =
        containerWidth -
        cardWidth -
        Math.abs(Math.sin((maxFanAngle * Math.PI) / 180) * cardHeight);
      const idealSpacing = cardWidth * (1 - overlapRatio);
      const actualSpacing =
        cardCount > 1
          ? Math.min(idealSpacing, availableWidth / (cardCount - 1))
          : 0;

      cards.forEach((card, index) => {
        // Calculate angle for this card
        const angle = startAngle + angleStep * index;
        const angleRad = (angle * Math.PI) / 180;

        // Calculate position along the fan arc
        const totalWidth = (cardCount - 1) * actualSpacing;
        const centerOffset = totalWidth / 2;
        const x =
          index * actualSpacing -
          centerOffset +
          containerWidth / 2 -
          cardWidth / 2;
        const y = Math.abs(Math.sin(angleRad)) * (fanRadius - cardHeight) * 0.5;

        // Z-index: center cards on top
        const zIndex = 50 + index * 10;

        // Apply transforms and styling
        card.style.position = "absolute";
        card.style.left = `${x}px`;
        card.style.bottom = "0";
        // card.style.transform = `translateY(${y}px) rotate(${angle}deg)`
        card.style.transformOrigin = "center bottom";
        card.style.zIndex = zIndex;
        // card.style.transition = 'transform 0.3s ease, z-index 0.3s ease'

        // Add tabindex for mobile accessibility
        card.setAttribute("tabindex", "0");

        // Store original transform for hover/focus effects
        card.dataset.originalTransform = card.style.transform;
        card.dataset.originalZIndex = zIndex;

        // Calculate hover transform (lift card and reduce rotation)
        const liftY = -15; // pixels to lift the card
        const hoverAngle = angle * 0.3; // reduce rotation by 70%
        const hoverTransform = `translateY(${y + liftY}px) rotate(${hoverAngle}deg) scale(1.05)`;

        // Set CSS custom properties for hover effect
        card.style.setProperty("--original-transform", card.style.transform);
        card.style.setProperty("--hover-transform", hoverTransform);
      });

      // Set container height to accommodate the fanned cards
      const maxY = Math.max(
        ...Array.from(cards).map((_, i) => {
          const angle = startAngle + angleStep * i;
          const angleRad = (angle * Math.PI) / 180;
          return Math.abs(Math.sin(angleRad)) * (fanRadius - cardHeight) * 0.1;
        }),
      );

      this.el.style.height = `${cardHeight + maxY}px`;
    }
  },
};

export default LayoutHand;
