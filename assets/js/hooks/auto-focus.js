// Focuses the element (or its first focusable field) when it mounts. Attach to
// something that appears in response to a server update — e.g. the alt-art
// artist form, which is added to the DOM once a target card is picked — so the
// cursor lands there with no extra click.
export default {
  mounted() {
    const target = this.el.querySelector("input, textarea, select") || this.el
    target.focus()
  },
}
