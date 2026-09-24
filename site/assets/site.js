// minimodeLL site: theme toggle, mobile nav, scroll reveal. No dependencies.
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.remove("no-js");

  // --- theme (system by default; explicit choice stored per browser) ---
  var THEME_KEY = "mm-theme";
  function stored() { try { return localStorage.getItem(THEME_KEY); } catch (e) { return null; } }
  function systemDark() { return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches; }
  function current() { var t = root.getAttribute("data-theme"); return t || (systemDark() ? "dark" : "light"); }
  function apply(theme, persist) {
    if (theme) { root.setAttribute("data-theme", theme); } else { root.removeAttribute("data-theme"); }
    if (persist) { try { theme ? localStorage.setItem(THEME_KEY, theme) : localStorage.removeItem(THEME_KEY); } catch (e) {} }
  }
  var saved = stored();
  if (saved === "dark" || saved === "light") { apply(saved, false); }
  document.querySelectorAll(".theme-toggle").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var next = current() === "dark" ? "light" : "dark";
      // If the choice matches the system, fall back to following the system.
      if ((next === "dark") === systemDark()) { apply(null, true); } else { apply(next, true); }
    });
  });

  // --- mobile navigation ---
  document.querySelectorAll(".nav-toggle").forEach(function (btn) {
    var target = document.getElementById(btn.getAttribute("aria-controls"));
    if (!target) { return; }
    btn.addEventListener("click", function () {
      var open = target.getAttribute("data-open") === "true";
      target.setAttribute("data-open", open ? "false" : "true");
      btn.setAttribute("aria-expanded", open ? "false" : "true");
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && target.getAttribute("data-open") === "true") {
        target.setAttribute("data-open", "false");
        btn.setAttribute("aria-expanded", "false");
        btn.focus();
      }
    });
  });

  // --- scroll reveal (respects reduced motion) ---
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var items = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach(function (el) { el.classList.add("in"); });
    return;
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) { entry.target.classList.add("in"); io.unobserve(entry.target); }
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
  items.forEach(function (el) { io.observe(el); });
})();
