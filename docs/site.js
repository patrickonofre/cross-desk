// site.js — vanilla, dependency-free (loaded with defer like i18n.js).
// Adapted from mac-metrics-view/docs/popover-demo.js, dropping the popover-tab
// widget (no interactive demo on this site): scroll-reveal + sticky-CTA only.
(function () {
  "use strict";

  function initReveal() {
    var reduce =
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var targets = document.querySelectorAll(".reveal-init");
    if (!targets.length) return;
    if (reduce) return;
    if (!("IntersectionObserver" in window)) {
      targets.forEach(function (el) {
        el.classList.add("reveal-in");
      });
      return;
    }
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("reveal-in");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    targets.forEach(function (el) {
      io.observe(el);
    });
  }

  function initStickyCta() {
    if (!document.querySelector("[data-sticky-cta]")) return;
    var suppressors = [].slice
      .call(document.querySelectorAll(".hero, #download"))
      .filter(Boolean);
    if (!suppressors.length || !("IntersectionObserver" in window)) return;
    var visible = new Set();
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) visible.add(entry.target);
          else visible.delete(entry.target);
        });
        if (visible.size) document.body.setAttribute("data-cta-hidden", "");
        else document.body.removeAttribute("data-cta-hidden");
      },
      { threshold: 0.15 }
    );
    suppressors.forEach(function (el) {
      io.observe(el);
    });
  }

  function boot() {
    initReveal();
    initStickyCta();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
