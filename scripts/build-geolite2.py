#!/usr/bin/env python3
"""
build-geolite2.py — GeoLite2-City.mmdb -> database biner ringkas untuk FreePN.

KENAPA BUKAN BUNDLE .mmdb LANGSUNG
  GeoLite2-City.mmdb ~48 MB dan aplikasi sudah 85 MB (mostly sing-box).
  Yang dipakai di aplikasi cuma tiga field: kode negara, koordinat kota,
  dan batas jaringan. Sisanya (kota, zona waktu, nama dalam 5 bahasa, ISP)
  dibuang saat build. Hasilnya 11 byte per jaringan.

HASIL
  magic  8 byte  "FPNGEO02"
  count  4 byte  UInt32 BE  — jumlah record
  ncodes 2 byte  UInt16 BE  — jumlah kode negara
  codes  ncodes x 2 byte    — kode negara ASCII, terurut
  record 11 byte, FIXED width:
      startIP UInt32 BE | span UInt16 BE | lat UInt16 BE | lng UInt16 BE | idx UInt8

 _fixed width_ dipilih supaya Swift bisa mencari langsung di berkas yang
  di-memory-map (stride 11) tanpa memuat 2,8 juta record ke RAM.

  Kenapa `span` HARUS ADA: pencarian adalah "record terakhir dengan
  start <= ip". Tanpa batas atas, IP yang jatuh di CELAH (blok privat
  10/8, 192.168/16, dsb — tidak ada di GeoLite2) akan mewarisi data
  record SEBELUMnya. Test menangkap 192.168.1.1 -> "ML" (Mali).

  Kenapa koordinat cukup 16 bit: skala 1/128 derajat ~ 870 m di
  khatulistiwa — jauh di bawah satu piksel peta dunia selebar ~300 pt,
  jadi tidak terlihat, dan menghemat 2 byte per record. Int24 (1e-7
  derajat) berlebihan untuk sebuah pin.

LISENSI
  GeoLite2 EULA mewajibkan atribusi ke MaxMind (§3) dan pembaruan <= 30
  hari (§6.3); §5 melarang memakai data ini untuk menemukan rumah/orang/
  alamat jalan tertentu. Data GeoNames di dalamnya CC BY 4.0.
  Lihat DECISIONS.md D55.

  Pembaca MMDB memakai paket `maxminddb` (Apache-2.0) — HANYA saat build,
  tidak masuk ke aplikasi.

PAKAI
  python3 -m pip install maxminddb
  scripts/build-geolite2.py /path/GeoLite2-City.mmdb [--out PATH]
"""
import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "FreePN", "Resources", "geoip-country.bin")

MAGIC = b"FPNGEO02"
COORD_SCALE = 128.0
MAX_SPAN = 0xFFFF

# Sanity check sebelum hasil dipakai massal: tiga IP yang negara &
# koordinatnya tidak mungkin berubah diam-diam.
PROBES = {
    "8.8.8.8": ("US", 37.751, -97.822),
    "39.103.165.178": ("CN", 39.911, 116.395),
    "154.90.39.63": ("MY", 3.141, 101.685),
}


def coord_bytes(value: float, bias: float) -> bytes:
    units = int(round((value + bias) * COORD_SCALE))
    units = max(0, min(0xFFFF, units))
    return bytes(((units >> 8) & 0xFF, units & 0xFF))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mmdb")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    try:
        from maxminddb.reader import Reader
    except ImportError:
        print("perlu: python3 -m pip install maxminddb", file=sys.stderr)
        return 1

    print("membaca %s (%.1f MB)" % (args.mmdb, os.path.getsize(args.mmdb) / 1048576))
    reader = Reader(args.mmdb)

    for ip, (expect_cc, _, _) in PROBES.items():
        got = ((reader.get(ip) or {}).get("country") or {}).get("iso_code")
        if got != expect_cc:
            print("SANITY GAGAL: %s -> %r (harus %r)" % (ip, got, expect_cc),
                  file=sys.stderr)
            return 1
    print("  sanity ok (%d probe)" % len(PROBES))

    # --- enumerasi jaringan ---------------------------------------------
    # `reader.__iter__` milik reader pure-Python ikut mendecode SELURUH
    # record (5,7 juta network x nama dalam 5 bahasa = ~12 menit). Jadi:
    # telusuri POHON saja lewat `_read_node` (murah), lalu decode sekali per
    # POINTER lewat reader ekstensi C (banyak jaringan berbagi satu record).
    import ipaddress
    import maxminddb.extension as _ext
    fast = _ext.Reader(args.mmdb)

    node_count = reader.metadata().node_count
    nets = []

    def walk(n, bits, depth):
        if depth > 32:
            return
        for index in (0, 1):
            rec = reader._read_node(n, index)
            if rec == node_count:
                continue                        # tidak ada data
            if rec > node_count:
                plen = depth + 1
                if plen > 32:
                    continue                    # sisa IPv6
                # Prefix sepanjang `plen` bit adalah (bits << 1) | index —
                # BIT `index` HARUS ikut, kalau tidak `start` meleset satu
                # bit dan semua jaringan tampak tumpang tindih.
                nets.append((((bits << 1) | index) << (32 - plen), plen, rec))
                continue
            walk(rec, (bits << 1) | index, depth + 1)

    walk(reader._ipv4_start, 0, 0)
    nets.sort()

    by_pointer = {}
    for start, plen, ptr in nets:
        by_pointer.setdefault(ptr, start)
    decoded = {}
    for ptr, start in by_pointer.items():
        value = fast.get(str(ipaddress.IPv4Address(start)))
        if isinstance(value, dict):
            code = (value.get("country") or {}).get("iso_code")
            loc = value.get("location") or {}
            lat, lon = loc.get("latitude"), loc.get("longitude")
            if code and lat is not None and lon is not None:
                decoded[ptr] = (code, float(lat), float(lon))
    reader.close()
    fast.close()

    entries = []
    for start, plen, ptr in nets:
        if ptr not in decoded:
            continue
        end = (start | ((1 << (32 - plen)) - 1)) if plen < 32 else start
        entries.append((start, decoded[ptr], end - start))

    # --- gabungkan rentang bersebelahan yang isinya identik ---------------
    # Tanpa pengorbanan akurasi: hanya Saves tempat.
    merged = []
    for start, value, span in entries:
        if merged:
            ms, mv, mspan = merged[-1]
            if mv == value and ms + mspan + 1 == start:
                merged[-1] = (ms, mv, mspan + span + 1)
                continue
        merged.append((start, value, span))

    # Buang tumpang tindih (defensif; trie MaxMind tidak menghasilkannya).
    clean = []
    for start, value, span in merged:
        if clean and start <= clean[-1][0] + clean[-1][2]:
            continue
        clean.append((start, value, span))

    # Pecah span yang melebihi MAX_SPAN supaya muat di 16 bit. Hanya ~1.500
    # record yang perlu, pengaruhnya ke ukuran file nihil.
    final = []
    for start, (code, lat, lon), span in clean:
        while span > MAX_SPAN:
            final.append((start, code, lat, lon, MAX_SPAN))
            start += MAX_SPAN + 1
            span -= MAX_SPAN + 1
        final.append((start, code, lat, lon, span))

    codes = sorted({r[1] for r in final})
    cidx = {c: i for i, c in enumerate(codes)}

    blob = bytearray()
    blob += MAGIC
    blob += struct.pack(">I", len(final))
    blob += struct.pack(">H", len(codes))
    for c in codes:
        blob += c.encode("ascii")
    for start, code, lat, lon, span in final:
        blob += struct.pack(">I", start)
        blob += struct.pack(">H", span)
        blob += coord_bytes(lat, 90.0)
        blob += coord_bytes(lon, 180.0)
        blob += bytes([cidx[code]])

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "wb") as fh:
        fh.write(blob)

    print("jaringan IPv4 : %d" % len(final))
    print("kode negara   : %d" % len(codes))
    print("tulis         : %s (%.2f MB)" % (args.out, len(blob) / 1048576))
    return 0


if __name__ == "__main__":
    sys.exit(main())