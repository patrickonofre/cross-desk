// Lightweight i18n for the static site. Mirrors mac-metrics-view/docs/i18n.js.
// Text nodes carry data-i18n="key". PT is the default language. The pt and en
// key sets MUST stay identical — scripts/check-i18n-parity.mjs enforces that.
(function () {
  "use strict";

  var STRINGS = {
    pt: {
      "nav.how": "Como funciona",
      "nav.features": "Recursos",
      "nav.privacy": "Privacidade",
      "nav.install": "Instalação",
      "nav.download": "Download",

      "hero.eyebrow": "Versão 1.2 para macOS",
      "hero.title": "Um cursor, todas as suas telas.",
      "hero.lede": "Compartilhe teclado e mouse entre Macs pela rede local, sem vídeo — o cursor cruza a borda da tela e passa a controlar o outro computador.",
      "hero.cta": "Baixar CrossDesk",
      "hero.secondary": "Ver como funciona",
      "hero.note": "Sem conta. Sem telemetria. Tráfego sempre criptografado.",
      "hero.badges": "1.2.1 · macOS 14+ · Código aberto (MIT) · mac ↔ mac",

      "sticky.label": "CrossDesk 1.2",
      "sticky.cta": "Baixar",

      "how.eyebrow": "Como funciona",
      "how.title": "Um servidor, um ou mais clientes.",
      "how.lede": "Um Mac é o servidor (dono do teclado e mouse); os outros são clientes. O cursor cruza a borda da tela como se fosse um único desktop.",
      "how.diagramServer": "Servidor",
      "how.diagramClient": "Cliente",
      "how.step1": "No servidor, escolha a borda da tela e o CrossDesk mostra o código de pareamento e o endereço.",
      "how.step2": "No cliente, informe o endereço e o código curto — o pareamento deriva a chave localmente, sem trafegar pela rede.",
      "how.step3": "Mova o cursor até a borda: o controle passa para o outro Mac. Esc 3× sempre devolve o controle ao servidor.",

      "features.eyebrow": "Feito para ser rápido e seguro",
      "features.title": "Rápido, simples e seguro por padrão.",
      "features.udpTitle": "Latência baixa",
      "features.udpBody": "Transporte UDP — sem o head-of-line blocking do TCP.",
      "features.securityTitle": "Criptografado por padrão",
      "features.securityBody": "DTLS-PSK em todo o tráfego. Sem modo texto-plano, nunca.",
      "features.pairTitle": "Pareamento simples",
      "features.pairBody": "Código curto (formato XXX-XXX) deriva a chave localmente nos dois lados.",
      "features.escTitle": "Esc×3 sempre funciona",
      "features.escBody": "Devolve o controle ao servidor mesmo com a rede caída — failsafe garantido.",
      "features.autostartTitle": "Abre com o sistema",
      "features.autostartBody": "Toggle \"Abrir ao iniciar sessão\" liga o autostart via SMAppService.",
      "features.updateTitle": "Atualização automática",
      "features.updateBody": "Baixa, verifica (EdDSA) e instala sozinho via Sparkle, sem passar pelo navegador.",
      "features.clipboardTitle": "Arquivos entre Macs",
      "features.clipboardBody": "Transferência de arquivos entre as máquinas pareadas via ⌘C/⌘V.",

      "privacy.eyebrow": "Privacidade e segurança",
      "privacy.title": "Nada trafega em texto plano.",
      "privacy.body": "O CrossDesk conecta os Macs por UDP com criptografia DTLS-PSK — sem modo texto-plano, sem conta e sem servidor na nuvem. O protocolo é público e documentado.",
      "privacy.li1": "Sem conta de usuário",
      "privacy.li2": "Sem telemetria dentro do app",
      "privacy.li3": "Protocolo aberto e versionado no repositório",

      "install.eyebrow": "Instalação",
      "install.title": "Ainda sem notarização da Apple — é esperado.",
      "install.lede": "O CrossDesk ainda não tem conta de desenvolvedor Apple, então o macOS bloqueia a primeira execução por precaução. Libere assim:",
      "install.s1Title": "Baixe e mova para Aplicativos",
      "install.s1Body": "Baixe o .zip da última release e mova o CrossDesk.app para a pasta Aplicativos.",
      "install.s2Title": "Remova a quarentena",
      "install.s2Body": "Abra o Terminal e rode: xattr -cr /Applications/CrossDesk.app",
      "install.s3Title": "Conceda as permissões",
      "install.s3Body": "Em Ajustes → Privacidade e Segurança: Monitoramento de Entrada no servidor, Acessibilidade no cliente.",
      "install.update": "Depois da primeira instalação, novas versões chegam pelo próprio app via Sparkle — sem passar pelo navegador de novo.",

      "download.eyebrow": "Download",
      "download.title": "Baixe a versão 1.2.1.",
      "download.body": "Para macOS 14 ou superior. Estável para mac ↔ mac; Windows e Linux nas próximas fases. Ainda não notarizado — veja a seção de instalação acima.",
      "download.cta": "Baixar no GitHub Releases",
      "download.meta": "macOS 14+ · Universal (Apple Silicon + Intel) · grátis e de código aberto (MIT)",

      "timeline.eyebrow": "Linha do tempo",
      "timeline.title": "De 1.0 a 1.2.1.",
      "timeline.lede": "Windows e Linux vêm em fases futuras — hoje o foco é mac ↔ mac.",
      "timeline.v121Title": "1.2.1 — Atualização automática, de verdade",
      "timeline.v121Body": "A v1.2.0 tinha uma chave de verificação placeholder — a checagem falhava em silêncio. Esta versão embute a chave EdDSA real e efetivamente instala atualizações sozinha.",
      "timeline.v120Title": "1.2.0 — Instala sozinho",
      "timeline.v120Body": "O botão \"Verificar Atualizações\" agora baixa, verifica e instala a nova versão sozinho, sem abrir o navegador.",
      "timeline.v112Title": "1.1.2 — Autostart mais confiável",
      "timeline.v112Body": "\"Abrir ao iniciar sessão\" não fica mais registrado sem funcionar quando o app roda de um caminho de quarentena.",
      "timeline.v110Title": "1.1.0 — Aviso de nova versão",
      "timeline.v110Body": "O app checa os Releases do GitHub e mostra um rótulo discreto no popover quando há versão nova.",
      "timeline.v100Title": "1.0.0 — Primeira versão estável",
      "timeline.v100Body": "KVM sem vídeo entre dois Macs, transporte UDP criptografado, descoberta automática na rede, pareamento por código, arquivos via ⌘C/⌘V, Esc×3 sempre funciona.",

      "footer.tagline": "Versão 1.2 para macOS",
      "footer.rights": "Código aberto · Licença MIT",
      "footer.github": "GitHub"
    },
    en: {
      "nav.how": "How it works",
      "nav.features": "Features",
      "nav.privacy": "Privacy",
      "nav.install": "Install",
      "nav.download": "Download",

      "hero.eyebrow": "Version 1.2 for macOS",
      "hero.title": "One cursor, all your screens.",
      "hero.lede": "Share keyboard and mouse between Macs over the local network, no video — the cursor crosses the screen edge and takes over the other computer.",
      "hero.cta": "Download CrossDesk",
      "hero.secondary": "See how it works",
      "hero.note": "No account. No telemetry. Traffic is always encrypted.",
      "hero.badges": "1.2.1 · macOS 14+ · Open source (MIT) · mac ↔ mac",

      "sticky.label": "CrossDesk 1.2",
      "sticky.cta": "Download",

      "how.eyebrow": "How it works",
      "how.title": "One server, one or more clients.",
      "how.lede": "One Mac is the server (owns the keyboard and mouse); the others are clients. The cursor crosses the screen edge as if it were a single desktop.",
      "how.diagramServer": "Server",
      "how.diagramClient": "Client",
      "how.step1": "On the server, pick the screen edge — CrossDesk shows the pairing code and address.",
      "how.step2": "On the client, enter the address and short code — pairing derives the key locally, nothing travels over the network.",
      "how.step3": "Move the cursor to the edge: control switches to the other Mac. Esc×3 always returns control to the server.",

      "features.eyebrow": "Built to be fast and secure",
      "features.title": "Fast, simple, and secure by default.",
      "features.udpTitle": "Low latency",
      "features.udpBody": "UDP transport — no TCP head-of-line blocking.",
      "features.securityTitle": "Encrypted by default",
      "features.securityBody": "DTLS-PSK on all traffic. No plaintext mode, ever.",
      "features.pairTitle": "Simple pairing",
      "features.pairBody": "Short code (XXX-XXX format) derives the key locally on both sides.",
      "features.escTitle": "Esc×3 always works",
      "features.escBody": "Returns control to the server even with the network down — a guaranteed failsafe.",
      "features.autostartTitle": "Opens with the system",
      "features.autostartBody": "The \"Open at login\" toggle enables autostart via SMAppService.",
      "features.updateTitle": "Automatic updates",
      "features.updateBody": "Downloads, verifies (EdDSA), and installs itself via Sparkle, without a browser detour.",
      "features.clipboardTitle": "Files between Macs",
      "features.clipboardBody": "Transfer files between paired machines via ⌘C/⌘V.",

      "privacy.eyebrow": "Privacy and security",
      "privacy.title": "Nothing travels in plaintext.",
      "privacy.body": "CrossDesk connects your Macs over UDP with DTLS-PSK encryption — no plaintext mode, no account, no cloud server. The protocol is public and documented.",
      "privacy.li1": "No user account",
      "privacy.li2": "No in-app telemetry",
      "privacy.li3": "Open, versioned protocol in the repository",

      "install.eyebrow": "Installation",
      "install.title": "Not notarized by Apple yet — that's expected.",
      "install.lede": "CrossDesk doesn't have an Apple Developer account yet, so macOS blocks the first launch as a precaution. Allow it like this:",
      "install.s1Title": "Download and move to Applications",
      "install.s1Body": "Download the latest release .zip and move CrossDesk.app to your Applications folder.",
      "install.s2Title": "Remove quarantine",
      "install.s2Body": "Open Terminal and run: xattr -cr /Applications/CrossDesk.app",
      "install.s3Title": "Grant permissions",
      "install.s3Body": "In System Settings → Privacy & Security: Input Monitoring on the server, Accessibility on the client.",
      "install.update": "After this first install, new versions arrive through the app itself via Sparkle — no more browser trips.",

      "download.eyebrow": "Download",
      "download.title": "Download version 1.2.1.",
      "download.body": "For macOS 14 or later. Stable for mac ↔ mac; Windows and Linux in future phases. Not notarized yet — see the install section above.",
      "download.cta": "Download on GitHub Releases",
      "download.meta": "macOS 14+ · Universal (Apple Silicon + Intel) · free and open source (MIT)",

      "timeline.eyebrow": "Timeline",
      "timeline.title": "From 1.0 to 1.2.1.",
      "timeline.lede": "Windows and Linux are coming in future phases — today the focus is mac ↔ mac.",
      "timeline.v121Title": "1.2.1 — Automatic updates, for real",
      "timeline.v121Body": "v1.2.0 shipped with a placeholder verification key — the check silently failed. This version embeds the real EdDSA key and actually installs updates on its own.",
      "timeline.v120Title": "1.2.0 — Installs itself",
      "timeline.v120Body": "The \"Check for Updates\" button now downloads, verifies, and installs the new version on its own, without opening a browser.",
      "timeline.v112Title": "1.1.2 — More reliable autostart",
      "timeline.v112Body": "\"Open at login\" no longer registers without working when the app runs from a quarantined path.",
      "timeline.v110Title": "1.1.0 — New-version notice",
      "timeline.v110Body": "The app checks GitHub Releases and shows a discreet label in the popover when a newer version is available.",
      "timeline.v100Title": "1.0.0 — First stable release",
      "timeline.v100Body": "Video-free KVM between two Macs, encrypted UDP transport, automatic network discovery, code-based pairing, files via ⌘C/⌘V, Esc×3 always works.",

      "footer.tagline": "Version 1.2 for macOS",
      "footer.rights": "Open source · MIT License",
      "footer.github": "GitHub"
    }
  };

  function pathLang() {
    var p = (location.pathname || "").replace(/index\.html$/, "").replace(/\/+$/, "");
    return /\/en$/.test(p) ? "en" : "pt";
  }

  function apply(lang) {
    var dict = STRINGS[lang] || STRINGS.pt;

    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n")];
      if (v != null) el.textContent = v;
    });
    document.querySelectorAll("[data-i18n-alt]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n-alt")];
      if (v != null) el.setAttribute("alt", v);
    });

    document.querySelectorAll("[data-lang-option]").forEach(function (btn) {
      var active = btn.getAttribute("data-lang-option") === lang;
      btn.setAttribute("aria-pressed", active ? "true" : "false");
      btn.classList.toggle("is-active", active);
    });
  }

  function init() {
    var lang = pathLang();
    document.documentElement.lang = lang === "pt" ? "pt-BR" : "en";
    apply(lang);

    var targets = lang === "en" ? { pt: "../", en: "./" } : { pt: "./", en: "en/" };
    document.querySelectorAll("[data-lang-option]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var to = targets[btn.getAttribute("data-lang-option")];
        if (to) location.href = to;
      });
    });
  }

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init);
    } else {
      init();
    }
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { STRINGS: STRINGS };
  }
})();
