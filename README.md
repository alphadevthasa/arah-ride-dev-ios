# ArahRide — iOS native

Satu proyek Xcode dengan dua target aplikasi terpisah:

- `ArahCustomer` (`id.arahride.customer`)
- `ArahDriver` (`id.arahride.driver`)

Keduanya memakai SwiftUI untuk layar, `MLNMapView` MapLibre melalui `UIViewRepresentable` untuk peta native, serta URLSession untuk HTTP dan WebSocket. Posisi Driver diambil dari Core Location ketika online. Ikon mobil bergerak halus di antara dua pembaruan lokasi; tombol **Lihat posisi Driver** mengarahkan peta Customer ke lokasi terbaru. Target Driver mengaktifkan background location; iOS menampilkan indikator lokasi sesuai aturan sistem.
Peta dapat diperbesar atau diperkecil dengan gestur cubit.

Pratinjau: [tampilan Customer dengan ikon mobil](docs/live-car.png).

## Demo alur pemesanan

GIF berikut merekam alur **Customer** (memesan, mencari Driver, hingga perjalanan berjalan) dan alur **Driver** (online, menerima pesanan, tiba, verifikasi PIN, menjalankan perjalanan) pada aplikasi iOS Dev/Portfolio:

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="docs/arah-ios-order-flow.gif" width="300" alt="Alur Customer iOS"><br>
      <sub><b>Customer</b> — pesan &amp; pantau perjalanan</sub>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="docs/arah-ios-driver-flow.gif" width="300" alt="Alur Driver iOS"><br>
      <sub><b>Driver</b> — online, terima pesanan, jalankan</sub>
    </td>
  </tr>
</table>

## Versi Production

Aplikasi **Production** punya alur lebih lengkap daripada Dev/Portfolio: login OTP (nomor telepon), pemilihan layanan (Motor/Mobil) dan metode pembayaran (tunai/non-tunai), estimasi tarif, pembayaran non-tunai, rating, dan tip. Repo ini berisi versi **Dev/Portfolio**; berikut cuplikan aplikasi **Customer** dan **Driver Production** sebagai gambaran seperti apa versi Production:

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="docs/arah-production-customer-flow.gif" width="300" alt="Production Customer iOS"><br>
      <sub><b>Customer Production</b> — order → perjalanan → bayar → tip</sub>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="docs/arah-production-driver-flow.gif" width="300" alt="Production Driver iOS"><br>
      <sub><b>Driver Production</b> — online → terima → tiba → PIN → perjalanan</sub>
    </td>
  </tr>
</table>

## Tech stack

- **Bahasa:** Swift
- **UI:** SwiftUI, dengan `UIViewRepresentable` untuk membungkus peta native
- **Peta:** MapLibre Native (`MLNMapView`) + tile OpenFreeMap (OpenStreetMap)
- **Networking:** URLSession — HTTP (REST) dan WebSocket untuk snapshot live
- **Lokasi:** Core Location (Driver), background location
- **Project:** di-generate dengan XcodeGen dari `project.yml` → `ArahRide.xcodeproj`
- **Target:** `ArahCustomer`, `ArahDriver`, `ArahRideTests`

## Menjalankan

1. Jalankan [Arah Ride Backend Dev](https://github.com/alphadevthasa/arah-ride-backend-dev).
2. Buka `ArahRide.xcodeproj` di Xcode. Jalankan `ArahDriver` dan `ArahCustomer` pada simulator; keduanya dapat terpasang bersamaan.
3. Aktifkan Driver, izinkan lokasi, pesan dari Customer, lalu terima dan selesaikan dari Driver. Untuk simulasi di Jakarta, set lokasi simulator di sekitar Jakarta.
4. Jika mengubah `project.yml`, jalankan `xcodegen generate` lagi.

Build terminal:

```sh
xcodebuild -project ArahRide.xcodeproj -scheme ArahCustomer -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project ArahRide.xcodeproj -scheme ArahDriver -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Default API simulator adalah `http://127.0.0.1:18080`. URL API dan style peta ada di `project.yml` sebagai `ArahAPIBaseURL` dan `ArahMapStyleURL`; regenerasi proyek setelah mengganti. Untuk perangkat fisik, gunakan hostname LAN yang bisa dijangkau. Untuk rilis, gunakan HTTPS dan hosting peta OSM dengan SLA atau milik sendiri.

Peta demo memakai [OpenFreeMap](https://openfreemap.org/quick_start/) dengan data OpenStreetMap dan atribusi terlihat. Ini adalah prototipe satu Driver/satu pesanan; batas server dan fitur produksi dijelaskan di README backend.

Backend demo mengambil geometri jalan dari OSRM dan menampilkannya sebagai polyline di peta. Saat Driver menekan **Mulai perjalanan**, lokasi simulasi dikirim tiap 100 ms selama 16 detik mengikuti polyline; lokasi perangkat Driver dijeda selama simulasi.

## Hasil verifikasi pencarian tempat (2026-06-28)

- Otomatis: iOS: `xcodebuild test -scheme ArahRideTests` lulus (18 test); build `ArahCustomer` dan `ArahDriver` lulus.
- Backend dengan Photon palsu lokal (`ARAH_GEOCODER_URL`): `/v1/places/search` dan `/v1/places/reverse` memetakan hasil dengan benar; kata kunci kosong → 400.
- **Belum diverifikasi**: Photon publik (`photon.komoot.io`) tidak terjangkau dari mesin ini saat pengujian (backend mengembalikan 502 generik), sehingga pencarian alamat/POI Indonesia sungguhan dan ketersediaan produksi tidak teruji. Uji emulator/simulator end-to-end (pilih titik, buat pesanan, label di app Driver, tap peta) juga belum dijalankan.
