const DragDrop = {
  async mounted() {
    const interact = (await import("interactjs")).default;

    interact(this.el).dropzone({
      ondrop: (event) => {
        console.log(event.relatedTarget);
        this.pushEvent("card-dropped", {
          card: event.relatedTarget.dataset.game_card_id, 
          zone: this.el.dataset.drop_zone,
          source_zone: event.relatedTarget.dataset.zone
        });
      },
    });
  },
};

export default DragDrop;
