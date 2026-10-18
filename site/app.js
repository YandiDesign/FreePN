(function () {
  var root = document.documentElement;
  root.classList.add('js');

  var META = {
    en: {
      title: 'FreePN: a free VPN client for macOS',
      desc: 'FreePN is a free, open source VPN client for macOS. Public VPN feeds tested for real reachability before they earn your connection. No accounts, no telemetry.'
    },
    id: {
      title: 'FreePN: client VPN gratis untuk macOS',
      desc: 'FreePN adalah client VPN gratis dan open source untuk macOS. Feed VPN publik diuji keterjangkauan nyatanya sebelum dipakai. Tanpa akun, tanpa telemetri.'
    }
  };

  var dict = {
    en: {
      skip: 'Skip to content',
      nav_how: 'How it works',
      nav_screens: 'Screens',
      cta_download: 'Download FreePN',
      cta_ghost: 'View on GitHub',
      hero_h1: 'A free VPN client for macOS.',
      hero_sub: 'Free public VPN feeds, tested for real reachability before they earn your connection. No accounts. No telemetry.',
      alt_connect: 'FreePN connected to a server: the power ring is on, live connections are listed, and the traffic graph is running.',
      verify_h2: 'Before it says Connected, it proves it.',
      step1_t: 'Write and validate',
      step1_b: 'Every connect assembles a fresh sing-box config: TUN routing, split rules, DNS. It must pass sing-box check before anything starts.',
      step2_t: 'Start and confirm',
      step2_b: 'The privileged helper launches the core as root. FreePN waits for the process to be alive and the Clash API to answer.',
      step3_t: 'Prove the exit',
      step3_b: "A request travels through the tunnel's own path to fetch your public IP. If it fails, you get an error. Not a green light.",
      verify_close: 'Dead nodes are marked as dead once they fail a real test. The ring only turns green when traffic actually flows.',
      screens_h2: 'The rest of the app.',
      alt_servers: "FreePN's server list: search and filters on top, protocol and latency columns, starred favorites.",
      cap_servers_t: 'Servers',
      cap_servers_b: 'Search thousands of nodes, filter by protocol or source, sort by latency, star favorites. Nodes that fail a real test are marked, and can be hidden.',
      alt_sources: "FreePN's sources screen: curated feed chips and a subscription URL field, with per-source status.",
      cap_sources_t: 'Sources',
      cap_sources_b: 'Paste any subscription URL. Clash YAML, base64 blobs, and raw share links are detected per source, with counts and HTTP errors shown plainly.',
      alt_mac: "FreePN's MAC address screen: current MAC, randomize and restore controls, and a history of changes.",
      cap_mac_t: 'MAC Address',
      cap_mac_b: 'Randomize or set a custom MAC, restore the original, and keep a searchable history of every change.',
      alt_settings: "FreePN's settings screen: update schedule, ping mode, CPU limit, UI scale, and language.",
      cap_settings_t: 'Settings',
      cap_settings_b: 'Refresh schedules, ping mode, CPU limits, UI scale, and the app language. The public IP check stays off until you enable it.',
      protos_h2: 'It speaks what free feeds speak.',
      protos_sub: 'Protocols',
      protos_note: 'Detected per node, deduplicated across feeds.',
      sources_sub: 'Sources',
      sources_b: 'A fresh install starts with zero sources. Ten curated community feeds wait as one-click chips; pick the ones you trust, or add your own subscription URL. Feeds that rotate their links daily are resolved automatically, up to seven days back.',
      alt_split: "FreePN's split tunneling screen: inclusive mode selected, a domain rule, the change log, and the app scanner.",
      split_caption: 'The change log records what was written to the config, before it can affect a connection.',
      split_h2: 'Decide what rides the tunnel.',
      split_p1: 'Inclusive sends only the apps you choose through the VPN. Exclusive tunnels everything and spares the apps you list. Rules match app bundle paths, so helper processes follow their parent, and individual domains can be routed by name.',
      split_p2: 'Every rule change is written to a change log: what was written, when, and when it takes effect.',
      split_p3: 'MAC address spoofing lives one screen over: randomize on connect, restore on disconnect, full history kept.',
      inside_h2: 'How it is built, and what it refuses to do.',
      c1_t: 'The core',
      c1a_b: 'sing-box 1.13.6 in a universal binary, behind a swappable interface.',
      c1b_b: 'Configs are validated with sing-box check before every connect. A failing config never runs.',
      c1c_b: 'Proxied DoH for tunneled traffic, system DNS for the rest. Lookups follow the same rules your packets do.',
      c2_t: 'The helper',
      c2a_b: 'A small launchd daemon runs the core with the privileges TUN mode needs, and nothing else.',
      c2b_b: 'It answers a fixed list of XPC commands: start, stop, status, version, and MAC get, set, or restore. No shell, no arbitrary paths.',
      c2c_b: "Before it answers, the helper verifies the caller's code signature. Anything but FreePN is refused.",
      c3_t: 'Your machine',
      c3a_b: 'No sign up, no email, no device ID. Open source under the MIT license.',
      c3b_b: 'Zero analytics, by construction. The only network calls are feed fetches, pings, and an IP check you can leave off.',
      c3c_b: 'Settings, rules, history: plain JSON under Application Support. Delete the folder and FreePN forgets everything.',
      inside_close: '574 unit tests ride along in the repository. The interface and this page both read English and Bahasa Indonesia.',
      warn_h2: 'Read this before trusting any free node.',
      warn_b: 'FreePN does not run its own servers. It collects feeds that anyone can operate, and a node operator can see unencrypted traffic passing through. Never sign in to banking, your primary email, or anything you cannot afford to lose while connected. This is a tool for reaching the open web, not for hiding who you are.',
      warn_close: 'Treat free nodes as public places: fine for browsing, wrong for secrets.',
      dl_h2: 'Put an honest tunnel on your Mac.',
      dl_b: 'FreePN 1.0 for macOS 13 Ventura and later, on Apple Silicon and Intel.',
      lb_close: 'Close',
      footer_tag: 'FreePN by YandiDesign. MIT licensed.',
      f_gh: 'GitHub',
      f_lic: 'License',
      f_rel: 'Releases',
      f_tp: 'Third-party licenses'
    },
    id: {
      skip: 'Lompat ke konten',
      nav_how: 'Cara kerja',
      nav_screens: 'Tampilan',
      cta_download: 'Unduh FreePN',
      cta_ghost: 'Lihat di GitHub',
      hero_h1: 'Client VPN gratis untuk macOS.',
      hero_sub: 'Feed VPN publik gratis, diuji keterjangkauan nyatanya sebelum dipakai. Tanpa akun. Tanpa telemetri.',
      alt_connect: 'FreePN terhubung ke server: cincin daya menyala, koneksi aktif terdaftar, dan grafik trafik berjalan.',
      verify_h2: 'Sebelum bilang Terhubung, FreePN membuktikannya.',
      step1_t: 'Tulis dan validasi',
      step1_b: 'Setiap koneksi menyusun config sing-box baru: routing TUN, aturan split, DNS. Wajib lolos sing-box check sebelum apa pun berjalan.',
      step2_t: 'Jalankan dan pastikan',
      step2_b: 'Helper berhak istimewa menjalankan core sebagai root. FreePN menunggu proses hidup dan Clash API menjawab.',
      step3_t: 'Buktikan jalur keluarnya',
      step3_b: 'Sebuah permintaan menempuh jalur tunnel itu sendiri untuk mengambil IP publik Anda. Kalau gagal, Anda mendapat error. Bukan lampu hijau.',
      verify_close: 'Node mati ditandai mati setelah gagal uji nyata. Cincin hanya menyala hijau ketika trafik benar-benar mengalir.',
      screens_h2: 'Sisi lain aplikasinya.',
      alt_servers: 'Daftar server FreePN: pencarian dan filter di atas, kolom protokol dan latensi, favorit berbintang.',
      cap_servers_t: 'Servers',
      cap_servers_b: 'Cari ribuan node, filter per protokol atau sumber, urutkan per latensi, tandai favorit. Node yang gagal uji nyata ditandai, dan bisa disembunyikan.',
      alt_sources: 'Layar sumber FreePN: chip feed kurasi dan kolom URL subscription, lengkap dengan status tiap sumber.',
      cap_sources_t: 'Sumber',
      cap_sources_b: 'Tempel URL subscription apa pun. Clash YAML, base64, dan share link mentah terdeteksi per sumber, lengkap dengan jumlah dan error HTTP apa adanya.',
      alt_mac: 'Layar MAC address FreePN: MAC saat ini, tombol random dan restore, serta riwayat perubahan.',
      cap_mac_t: 'MAC Address',
      cap_mac_b: 'Random atau atur MAC custom, kembalikan ke aslinya, dan simpan riwayat yang bisa dicari.',
      alt_settings: 'Layar pengaturan FreePN: jadwal update, mode ping, batas CPU, skala UI, dan bahasa.',
      cap_settings_t: 'Pengaturan',
      cap_settings_b: 'Jadwal refresh, mode ping, batas CPU, skala UI, dan bahasa aplikasi. Cek IP publik tetap mati sampai Anda menyalakannya.',
      protos_h2: 'Bicara semua protokol yang dipakai feed gratis.',
      protos_sub: 'Protokol',
      protos_note: 'Terdeteksi per node, duplikat antar-feed digabung.',
      sources_sub: 'Sumber',
      sources_b: 'Instalasi baru mulai dari nol sumber. Sepuluh feed komunitas pilihan menunggu sebagai chip sekali-klik; pilih yang Anda percaya, atau tambahkan URL subscription sendiri. Feed yang mengganti link tiap hari diresolusi otomatis, sampai tujuh hari ke belakang.',
      alt_split: 'Layar split tunneling FreePN: mode inclusive terpilih, aturan domain, change log, dan pemindai aplikasi.',
      split_caption: 'Change log mencatat apa yang ditulis ke config, sebelum bisa memengaruhi koneksi.',
      split_h2: 'Tentukan apa yang lewat tunnel.',
      split_p1: 'Inclusive mengirim hanya aplikasi pilihan Anda lewat VPN. Exclusive men-tunnel semua dan mengecualikan aplikasi yang Anda daftarkan. Aturan dicocokkan lewat bundle path, jadi proses helper ikut induknya, dan domain individual bisa dirutekan per nama.',
      split_p2: 'Setiap perubahan aturan tercatat di change log: apa yang ditulis, kapan, dan kapan berlaku.',
      split_p3: 'MAC address spoofing ada di layar sebelah: random saat connect, restore saat disconnect, riwayat lengkap.',
      inside_h2: 'Cara FreePN dibangun, dan apa yang tidak mau dilakukannya.',
      c1_t: 'Core',
      c1a_b: 'sing-box 1.13.6 dalam universal binary, di balik antarmuka yang bisa diganti.',
      c1b_b: 'Config divalidasi dengan sing-box check sebelum setiap koneksi. Config yang gagal tidak pernah berjalan.',
      c1c_b: 'DoH lewat proxy untuk trafik tunnel, DNS sistem untuk sisanya. Lookup mengikuti aturan yang sama dengan paket Anda.',
      c2_t: 'Helper',
      c2a_b: 'Daemon launchd kecil menjalankan core dengan hak akses yang dibutuhkan mode TUN, tidak lebih.',
      c2b_b: 'Helper menjawab daftar XPC tetap: start, stop, status, version, dan MAC get, set, restore. Tanpa shell, tanpa path bebas.',
      c2c_b: 'Sebelum menjawab, helper memverifikasi code signature pemanggil. Selain FreePN, ditolak.',
      c3_t: 'Data Anda',
      c3a_b: 'Tanpa daftar, tanpa email, tanpa device ID. Open source dengan lisensi MIT.',
      c3b_b: 'Nol analytics, dari konstruksinya. Koneksi keluar hanya: ambil feed, ping, dan cek IP yang bisa Anda biarkan mati.',
      c3c_b: 'Pengaturan, aturan, riwayat: JSON biasa di Application Support. Hapus foldernya, FreePN lupa semuanya.',
      inside_close: '574 unit test ikut dalam repo. Antarmuka dan halaman ini sama-sama membaca Bahasa Indonesia dan English.',
      warn_h2: 'Baca ini sebelum memercayai node gratis mana pun.',
      warn_b: 'FreePN tidak menjalankan server sendiri. Aplikasi mengumpulkan feed yang bisa dioperasikan siapa saja, dan operator node bisa melihat trafik tak terenkripsi yang lewat. Jangan pernah login ke bank, email utama, atau apa pun yang tak ingin Anda kehilangan saat terhubung. Ini alat untuk menjangkau internet terbuka, bukan untuk menyembunyikan identitas.',
      warn_close: 'Perlakukan node gratis seperti ruang publik: cocok untuk menjelajah, bukan untuk rahasia.',
      dl_h2: 'Pasang tunnel yang jujur di Mac Anda.',
      dl_b: 'FreePN 1.0 untuk macOS 13 Ventura ke atas, di Apple Silicon dan Intel.',
      lb_close: 'Tutup',
      footer_tag: 'FreePN oleh YandiDesign. Lisensi MIT.',
      f_gh: 'GitHub',
      f_lic: 'Lisensi',
      f_rel: 'Rilis',
      f_tp: 'Lisensi pihak ketiga'
    }
  };

  function norm(lang) {
    return (lang || '').toLowerCase().indexOf('id') === 0 ? 'id' : 'en';
  }

  var saved = null;
  try {
    saved = localStorage.getItem('freepn-lang');
  } catch (e) {}

  var lang = norm(saved || navigator.language || 'en');

  function apply(l) {
    var d = dict[l];

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var k = el.getAttribute('data-i18n');
      if (d[k] != null) el.textContent = d[k];
    });

    document.querySelectorAll('[data-i18n-alt]').forEach(function (el) {
      var k = el.getAttribute('data-i18n-alt');
      if (d[k] != null) el.alt = d[k];
    });

    document.title = META[l].title;
    var meta = document.querySelector('meta[name="description"]');
    if (meta) meta.setAttribute('content', META[l].desc);

    root.lang = l;

    var btn = document.getElementById('langToggle');
    if (btn) {
      btn.textContent = l === 'en' ? 'Bahasa Indonesia' : 'English';
      btn.setAttribute('aria-label', l === 'en' ? 'Ganti ke Bahasa Indonesia' : 'Switch to English');
    }
  }

  apply(lang);

  var toggle = document.getElementById('langToggle');
  if (toggle) {
    toggle.addEventListener('click', function () {
      lang = lang === 'en' ? 'id' : 'en';
      try {
        localStorage.setItem('freepn-lang', lang);
      } catch (e) {}
      apply(lang);
    });
  }

  var lightbox = document.getElementById('lightbox');
  var lightboxImg = document.getElementById('lightboxImg');
  var lightboxClose = document.getElementById('lightboxClose');
  var lastFocus = null;

  function openLightbox(source) {
    lightboxImg.src = source.currentSrc || source.src;
    lightboxImg.alt = source.alt;
    lastFocus = document.activeElement;
    lightbox.hidden = false;
    void lightbox.offsetWidth;
    lightbox.classList.add('open');
    root.classList.add('lb-open');
    lightboxClose.focus();
  }

  function closeLightbox() {
    lightbox.classList.remove('open');
    root.classList.remove('lb-open');
    window.setTimeout(function () {
      lightbox.hidden = true;
      lightboxImg.removeAttribute('src');
      if (lastFocus) lastFocus.focus();
    }, 260);
  }

  if (lightbox) {
    document.querySelectorAll('.shot-zoom').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var img = btn.querySelector('img');
        if (img) openLightbox(img);
      });
    });

    lightboxClose.addEventListener('click', closeLightbox);

    lightbox.addEventListener('click', function (e) {
      if (e.target === lightbox) closeLightbox();
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && !lightbox.hidden) closeLightbox();
    });
  }

  var reveals = document.querySelectorAll('.reveal');
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (reduce || !('IntersectionObserver' in window)) {
    reveals.forEach(function (el) {
      el.classList.add('in');
    });
    return;
  }

  var io = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
  );

  reveals.forEach(function (el) {
    io.observe(el);
  });
})();
