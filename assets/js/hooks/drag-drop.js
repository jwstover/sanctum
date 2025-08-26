const DragDrop = {
  async mounted() {
    const interact = (await import("interactjs")).default;

    interact(this.el)
      .dropzone({
        ondrop: (event) => {
          this.pushEvent("card-dropped", {
            card: event.relatedTarget.dataset.game_card_id,
            zone: this.el.dataset.drop_zone,
            source_zone: event.relatedTarget.dataset.zone,
          });
        },
      })
      .on("dropactivate", function (event) {
        event.target.classList.add("!border-blue-400");
      })
      .on("dropdeactivate", function (event) {
        event.target.classList.remove("!border-blue-400");
        event.target.classList.remove("!border-orange-400");
      })
      .on("dragenter", function (event) {
        event.target.classList.remove("!border-blue-400");
        event.target.classList.add("!border-orange-400");
      })
      .on("dragleave", function (event) {
        event.target.classList.add("!border-blue-400");
        event.target.classList.remove("!border-orange-400");
      })
    ;
  },
};

export default DragDrop;
