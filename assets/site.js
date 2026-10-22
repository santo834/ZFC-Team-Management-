const routeSegments = location.pathname.split("/").filter(Boolean);
const lastSegment = routeSegments.at(-1) || "";
const directory = lastSegment === "index.html" ? routeSegments.at(-2) : lastSegment;
const routeSection = routeSegments.length > 1 ? routeSegments.at(-2) : directory;
if (["teams", "drivers", "news"].includes(routeSection)) {
  location.replace("../index.html");
}
if ((lastSegment === "index.html" || !lastSegment.includes(".")) && ["sponsors", "hq"].includes(directory)) {
  location.replace("shop.html");
}

const publicDestinations = new Set(["insurance/", "sponsors/", "hq/", "marketplace/"]);
document.querySelectorAll(".topbar > .nav, .topbar .menu nav").forEach((navigation) => {
  navigation.querySelectorAll("a").forEach((link) => {
    const destination = new URL(link.href, location.href);
    const segments = destination.pathname.split("/").filter(Boolean);
    const section = segments.at(-2);
    if (!publicDestinations.has(`${section}/`)) {
      link.remove();
      return;
    }
    if ((section === "sponsors" || section === "hq") && segments.at(-1) === "index.html") {
      destination.pathname = destination.pathname.replace(/index\.html$/, "shop.html");
      link.href = destination.href;
    }
  });
});
document.querySelectorAll(".topbar .login-link").forEach((link) => link.remove());

document.querySelectorAll("[data-directory]").forEach((directory) => {
  const cards = [...directory.querySelectorAll("[data-entry]")];
  const search = directory.querySelector("[data-search]");
  const filters = [...directory.querySelectorAll("[data-filter]")];
  const pagination = directory.querySelector("[data-pagination]");
  const resultCount = directory.querySelector("[data-result-count]");
  const pageSize = Number(directory.dataset.pageSize || 8);
  let page = 0;

  function render() {
    const term = (search?.value || "").trim().toLowerCase();
    const matches = cards.filter((card) => {
      const textMatch = !term || card.textContent.toLowerCase().includes(term);
      const filterMatch = filters.every((filter) => !filter.value || card.dataset[filter.dataset.filter] === filter.value);
      return textMatch && filterMatch;
    });
    const pages = Math.max(1, Math.ceil(matches.length / pageSize));
    page = Math.min(page, pages - 1);
    cards.forEach((card) => { card.hidden = !matches.includes(card) || matches.indexOf(card) < page * pageSize || matches.indexOf(card) >= (page + 1) * pageSize; });
    if (resultCount) resultCount.textContent = `${matches.length} Einträge`;
    if (pagination) {
      pagination.hidden = matches.length <= pageSize;
      pagination.querySelector("[data-prev]").disabled = page === 0;
      pagination.querySelector("[data-next]").disabled = page + 1 >= pages;
      pagination.querySelector("[data-page-label]").textContent = `Seite ${page + 1} von ${pages}`;
    }
    const empty = directory.querySelector("[data-empty]");
    if (empty) empty.hidden = matches.length !== 0;
  }

  search?.addEventListener("input", () => { page = 0; render(); });
  filters.forEach((filter) => filter.addEventListener("change", () => { page = 0; render(); }));
  pagination?.querySelector("[data-prev]").addEventListener("click", () => { page -= 1; render(); });
  pagination?.querySelector("[data-next]").addEventListener("click", () => { page += 1; render(); });
  render();
});