export default {
  async mounted(el) {
    const interact = (await import("interactjs")).default;

    const container = document.querySelector("#game-board");

    interact(this.el)
      .draggable({
        inertia: false,
        // manualStart: true,
        hold: 500,
        modifiers: [
          interact.modifiers.restrictRect({
            restriction: container,
            endOnly: true,
          }),
        ],
        listeners: {
          start(event) {
            // Initialize position data on the element if it doesn't exist
            event.target.dataset.x = event.target.dataset.x || 0;
            event.target.dataset.y = event.target.dataset.y || 0;

            event.target.style.transform = "translate(0px, 0px)";
            event.target.style.scale = 1.2;

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
          }
        },
      })
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
