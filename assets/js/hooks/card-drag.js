export default {
  async mounted(el) {
    const interact = (await import("interactjs")).default;

    const container = document.querySelector("#game-board");

    interact(this.el)
      .draggable({
        inertia: false,
        // manualStart: true,
        // hold: 500,
        modifiers: [
          interact.modifiers.restrictRect({
            restriction: container,
            endOnly: true,
          }),
        ],
        listeners: {
          start(event) {
            // Initialize position data on the element if it doesn't exist
            const boundingRect = event.target.getBoundingClientRect();
            console.log(boundingRect);

            event.target.dataset.x = 0;
            event.target.dataset.y = 0;
            event.target.dataset.starting_left = event.target.style.left;
            event.target.dataset.starting_pos = event.target.style.position;

            event.target.style.left = `${boundingRect.x}px`;
            event.target.style.top = `${boundingRect.y}px`;
            event.target.style.position = "fixed";
            event.target.style.bottom = null;
            event.target.style.zIndex = 1001;
            event.target.style.transform = "translate(0px, 0px)";
            event.target.style.scale = 1.2;
            event.target.classList.add("game-card-dragging");
          },
          move(event) {
            const target = event.target;
            const x = (parseFloat(target.dataset.x) || 0) + event.dx;
            const y = (parseFloat(target.dataset.y) || 0) + event.dy;

            target.style.transform = `translate(${x}px, ${y}px)`;
            target.dataset.x = x;
            target.dataset.y = y;
          },
          end(event) {
            event.target.style.scale = 1;
            event.target.style.position = event.target.dataset.starting_pos;
            event.target.style.bottom = "0px";
            event.target.style.zIndex = null;
            event.target.style.transform = null;
            event.target.style.left = event.target.dataset.starting_left;
            event.target.style.top = null;
            event.target.classList.remove("game-card-dragging");
          },
        },
      })
      .on("dragend", function (event) {
        event.target.addEventListener(
          "click",
          (event) => event.stopImmediatePropagation(),
          { capture: true, once: true },
        );
      });
    // .on("tap", (event) => {
    //   console.log("tap")
    //   let interaction = event.interaction;
    //
    //   if (!interaction.interacting()) {
    //     interaction.start(
    //       { name: "drag" },
    //       event.interactable,
    //       event.currentTarget,
    //     );
    //   }
    // })
    // .on("drop", (event) => {
    //   console.log("stop")
    //   let interaction = event.interaction;
    //   if (interaction.interacting()) {
    //     interaction.stop();
    //   }
    // });
  },
};
