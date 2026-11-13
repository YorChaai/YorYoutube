import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('Audit UI: Dropdown Tab Navigation, Minimal Compact Mode, Refresh YouTube button, and Filters', (WidgetTester tester) async {
    String? mockClipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          mockClipboard = (call.arguments as Map?)?['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': mockClipboard};
        }
        return null;
      },
    );
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(const PersonalYouTubeApp());
    await tester.pumpAndSettle();

    // 1. Cek Sidebar Subscriptions tampil
    expect(find.text('Fajrul Fx'), findsWidgets);
    expect(find.text('Ferry Irwandi'), findsWidgets);

    // 2. Cek Tombol Refresh YouTube tersedia di header
    expect(find.text('Refresh YouTube'), findsOneWidget);

    // 3. Cek 3 Tombol Sortir & Pilihan Permanen 25/50/100 Video
    expect(find.text('🔥 View Terbanyak'), findsOneWidget);
    expect(find.text('👍 Like Terbanyak'), findsOneWidget);
    expect(find.text('🕒 Waktu Upload'), findsOneWidget);
    expect(find.text('25 Video'), findsOneWidget);
    expect(find.text('50 Video'), findsOneWidget);
    expect(find.text('100 Video'), findsOneWidget);

    // 4. Cek Dropdown Navigasi Tab + Tombol Kiri (Sebelumnya) & Kanan (Berikutnya)
    expect(find.text('Total: 36 video'), findsOneWidget);
    expect(find.text('Tab 1 (1–25)'), findsWidgets);
    expect(find.text('Sebelumnya'), findsWidgets);
    expect(find.text('Berikutnya'), findsWidgets);

    // Klik Berikutnya -> pindah ke Tab 2 (26–36)
    await tester.tap(find.text('Berikutnya').first);
    await tester.pumpAndSettle();
    expect(find.text('Tab 2 (26–36)'), findsWidgets);

    // 5. Cek Fitur Minimalisasi Filter Bar (Compact Mode)
    expect(find.text('Minimal'), findsOneWidget);
    await tester.tap(find.text('Minimal'));
    await tester.pumpAndSettle();
    expect(find.text('Buka Filter'), findsOneWidget);

    // Buka kembali filter
    await tester.tap(find.text('Buka Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Minimal'), findsOneWidget);

    // 6. Pastikan tombol '🔕 Unsubscribe' di bawah kartu video sudah dihapus (cukup lewat titik 3)
    expect(find.text('🔕 Unsubscribe'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsWidgets);

    // 7. Pastikan filter waktu sampai Tahun Ini + Input Tahun Lalu tersedia
    expect(find.text('Tahun Ini'), findsOneWidget);
    expect(find.text('Tahun Lalu'), findsOneWidget);

    // 8. Buka menu titik 3 kartu video -> cek opsi Transkrip & popup 3 prompt sejajar + TubeTranscript
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Tonton di YouTube'), findsOneWidget);
    expect(find.text('Transkrip'), findsOneWidget);

    await tester.tap(find.text('Transkrip'));
    await tester.pumpAndSettle();
    expect(find.text('Transkrip + Prompt'), findsOneWidget);
    expect(find.text('Gunakan TubeTranscript.com'), findsOneWidget);
    expect(find.text('Kutip'), findsOneWidget);
    expect(find.text('Formal'), findsOneWidget);
    expect(find.text('2.0'), findsOneWidget);

    // Aktifkan centang TubeTranscript lalu pilih prompt 2.0 -> masuk step Paste Transkrip
    await tester.tap(find.text('Gunakan TubeTranscript.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0'));
    await tester.pumpAndSettle();
    expect(find.text('Prompt "2.0" siap diisi dari TubeTranscript'), findsOneWidget);
    expect(find.text('Paste Transkrip'), findsOneWidget);

    // Simulasikan paste transkrip -> klik Paste Transkrip -> Siap 100% -> Copy -> balik ke menu prompt
    await tester.enterText(
      find.byType(TextField).last,
      'Ini contoh teks transkrip dari TubeTranscript.',
    );
    await tester.tap(find.text('Paste Transkrip'));
    await tester.pumpAndSettle();
    expect(find.text('Transkrip + Prompt 2.0 Siap (100%)'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Kutip'), findsOneWidget);
    expect(find.text('Formal'), findsOneWidget);
    expect(find.text('2.0'), findsOneWidget);
    expect(find.text('Gunakan TubeTranscript.com'), findsOneWidget);
    expect(mockClipboard, contains('Ini contoh teks transkrip dari TubeTranscript.'));

    // Uji 1-tap Paste Transkrip langsung dari Clipboard (tanpa ketik manual) dengan prompt Formal
    mockClipboard = 'Teks clipboard langsung dari TubeTranscript.';
    await tester.tap(find.text('Formal'));
    await tester.pumpAndSettle();
    expect(find.text('Prompt "Formal" siap diisi dari TubeTranscript'), findsOneWidget);
    await tester.tap(find.text('Paste Transkrip'));
    await tester.pumpAndSettle();
    expect(find.text('Transkrip + Prompt Formal Siap (100%)'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(mockClipboard, contains('Teks clipboard langsung dari TubeTranscript.'));
    expect(find.text('Kutip'), findsOneWidget);
    expect(find.text('Gunakan TubeTranscript.com'), findsOneWidget);

    // Tutup popup dengan tombol silang (X) di kanan atas
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Transkrip + Prompt'), findsNothing);
  });
}
