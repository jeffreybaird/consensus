// Theme switch (.claude/design-system.md): dark is the default; an explicit
// choice is stamped as data-theme and persisted. The layout's inline head
// script applies the saved choice before first paint; this module handles the
// toggle and keeps its pressed state honest. Print always renders light via
// the print stylesheet regardless.
(() => {
  const root = document.documentElement;

  const sync = () => {
    const pressed = root.getAttribute("data-theme") === "light";
    document.querySelectorAll("[data-theme-toggle]")
      .forEach((b) => b.setAttribute("aria-pressed", String(pressed)));
  };
  sync();

  document.addEventListener("click", (e) => {
    if (!e.target.closest("[data-theme-toggle]")) return;
    const next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("theme", next); } catch (e2) { /* private mode */ }
    sync();
  });
})();
