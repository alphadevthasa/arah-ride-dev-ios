import SwiftUI

struct RideScreen: View {
    let role: String
    @StateObject private var store: RideStore
    private let navy = Color(red: 0.08, green: 0.14, blue: 0.23)

    init(role: String) {
        self.role = role
        _store = StateObject(wrappedValue: RideStore(role: role))
    }

    var body: some View {
        ZStack {
            RideMap(role: role, snapshot: store.snapshot, pickup: $store.pickup, dropoff: $store.dropoff,
                    selection: store.selection, focusDriverRequest: store.focusDriverRequest)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(role == "driver" ? "ARAH / DRIVER" : "ARAH").font(.headline).bold()
                        Spacer()
                        Text(store.snapshot?.driverOnline == true ? "● Driver online" : "○ Driver offline").font(.caption)
                    }
                    Text("Peta © OpenStreetMap contributors · OpenFreeMap").font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(navy)
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    if let error = store.error {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                    if role == "customer" { customerPanel } else { driverPanel }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding(16)
            }
        }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    @ViewBuilder private var customerPanel: some View {
        if let ride = store.snapshot?.ride {
            switch ride.status {
            case "requested":
                title("Mencari Driver")
                Text("Pesanan terkirim. Driver akan segera merespons.")
                action("Batalkan pesanan", "cancel")
            case "accepted":
                title("Driver menuju titik jemput")
                driverInfo(ride)
                Text("Posisi Driver tampil langsung di peta.")
                focusDriverButton
                action("Batalkan pesanan", "cancel")
            case "arrived":
                title("Driver sudah tiba")
                driverInfo(ride)
                Text("Temui Driver di titik jemput.")
                focusDriverButton
            case "in_progress":
                title("Perjalanan berlangsung")
                driverInfo(ride)
                Text("Posisi Driver diperbarui langsung.")
                focusDriverButton
            case "completed":
                title("Perjalanan selesai")
                Text("Terima kasih sudah menggunakan Arah.")
                action("Pesan lagi", "reset")
            default:
                title("Pesanan dibatalkan")
                action("Buat pesanan baru", "reset")
            }
        } else {
            title("Mau ke mana hari ini?")
            Text("Ketuk peta untuk memilih titik. Pilih jenis titik dahulu.").font(.subheadline)
            HStack {
                selection("Jemput", "pickup")
                selection("Tujuan", "dropoff")
            }
            Text("Jemput: \(store.pickup.label)").font(.caption)
            Text("Tujuan: \(store.dropoff.label)").font(.caption)
            Button(store.snapshot?.driverOnline == true ? "Pesan perjalanan" : "Menunggu Driver online") {
                store.send("create")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.snapshot?.driverOnline != true)
        }
    }

    @ViewBuilder private var driverPanel: some View {
        if let state = store.snapshot {
            if !state.driverOnline {
                title("Siap menerima pesanan?")
                Text("Aktifkan status online. Lokasi dibagikan kepada Customer saat online.")
                action("Mulai online", "online")
            } else if let ride = state.ride, !["completed", "cancelled"].contains(ride.status) {
                switch ride.status {
                case "requested":
                    title("Pesanan baru")
                    tripPoints(ride)
                    action("Terima pesanan", "accept")
                case "accepted":
                    title("Menuju penjemputan")
                    tripPoints(ride)
                    action("Saya sudah tiba", "arrive")
                case "arrived":
                    title("Menunggu Customer")
                    tripPoints(ride)
                    action("Mulai perjalanan", "start")
                default:
                    title("Dalam perjalanan")
                    tripPoints(ride)
                    action("Selesaikan perjalanan", "complete")
                }
            } else {
                title("Anda online")
                Text("Menunggu pesanan baru di sekitar Anda.")
                action("Berhenti online", "offline")
            }
        } else {
            title("Menghubungkan...")
        }
    }

    private func title(_ text: String) -> some View { Text(text).font(.title2).bold() }
    private func driverInfo(_ ride: Ride) -> some View { Text("\(ride.driverName) · \(ride.driverPlate)").fontWeight(.semibold) }
    private func tripPoints(_ ride: Ride) -> some View {
        VStack(alignment: .leading) {
            Text("Jemput: \(ride.pickup.label)")
            Text("Tujuan: \(ride.dropoff.label)")
        }.font(.subheadline)
    }
    private func action(_ label: String, _ name: String) -> some View {
        Button(label) { store.send(name) }
            .buttonStyle(.borderedProminent)
            .tint(navy)
            .frame(maxWidth: .infinity)
    }
    private var focusDriverButton: some View {
        Button("Lihat posisi Driver") { store.focusDriver() }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }
    private func selection(_ label: String, _ key: String) -> some View {
        Button(store.selection == key ? "● \(label)" : label) { store.selection = key }
            .buttonStyle(.bordered)
    }
}
