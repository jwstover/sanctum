const DragDrop = {
  async mounted() {
    const interact = (await import("interactjs")).default;

    interact(this.el).dropzone({
      ondrop: (event) => {
        console.log(event.relatedTarget);
        this.pushEvent("card-dropped", {card: event.relatedTarget.id, zone: this.el.dataset.drop_zone});
      },
    });
  },
};

export default DragDrop;
