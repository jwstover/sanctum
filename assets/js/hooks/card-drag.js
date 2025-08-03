export default {
  async mounted(el) {
    const interact = (await import("interactjs")).default;

    console.log(interact);

    const container = document.querySelector("#game-board");

    interact(".game-card").draggable({
      inertia: false,
      modifiers: [
        interact.modifiers.restrictRect({
          restriction: container,
          endOnly: true,
        }),
      ],
      listeners: {
        start(event) {
          console.log(event.type, event.target);
          // Initialize position data on the element if it doesn't exist
          event.target.dataset.x = event.target.dataset.x || 0;
          event.target.dataset.y = event.target.dataset.y || 0;
        },
        move(event) {
          const target = event.target;
          const x = (parseFloat(target.dataset.x) || 0) + event.dx;
          const y = (parseFloat(target.dataset.y) || 0) + event.dy;

          target.style.transform = `translate(${x}px, ${y}px)`;
          target.dataset.x = x;
          target.dataset.y = y;
        },
      },
    });
  },
};
