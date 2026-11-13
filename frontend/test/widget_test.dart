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

    // 3. Cek Tombol Sortir & Pilihan Permanen 25/50/100 Video
    expect(find.text('🔥 View Terbanyak'), findsOneWidget);
    expect(find.text('👍 Like Terbanyak'), findsOneWidget);
    expect(find.text('🕒 Terbaru ke Terlama'), findsOneWidget);
    expect(find.text('⏳ Terlama ke Terbaru'), findsOneWidget);
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

    // 7. Pastikan filter waktu All Time, Today, This Week, This Month, This Year, Custom Date, Custom Date Range + Tahun Lalu tersedia
    expect(find.text('All Time'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('This Year'), findsOneWidget);
    expect(find.text('Custom Date'), findsOneWidget);
    expect(find.text('Custom Date Range'), findsOneWidget);
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

  testWidgets('Period Filters, Sorting (Newest/Oldest), Custom Date & Custom Date Range Calendar', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(const PersonalYouTubeApp());
    await tester.pumpAndSettle();

    // Uji pengurutan Terbaru <-> Terlama bersamaan dengan filter periode
    await tester.tap(find.text('⏳ Terlama ke Terbaru'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 36 video'), findsOneWidget);

    await tester.tap(find.text('This Year'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Time'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 36 video'), findsOneWidget);

    // Uji Custom Date Calendar: penanda hijau pada hari ini, tanggal masa depan nonaktif
    await tester.tap(find.text('Custom Date'));
    await tester.pumpAndSettle();
    expect(find.text('Hari Ini'), findsOneWidget);
    expect(find.text('Tanggal masa depan nonaktif'), findsOneWidget);

    final now = DateTime.now();
    final todayKey = Key('cal_day_${now.year}_${now.month}_${now.day}');
    final todayFinder = find.byKey(todayKey);
    expect(todayFinder, findsOneWidget);
    final todayBox = tester.widget<Container>(
      find.descendant(of: todayFinder, matching: find.byType(Container)),
    );
    final todayDeco = todayBox.decoration as BoxDecoration?;
    expect(todayDeco?.border?.top.color, Colors.green);

    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    if (now.day < daysInMonth) {
      final futureKey = Key('cal_day_${now.year}_${now.month}_${now.day + 1}');
      final futureInk = tester.widget<InkWell>(find.byKey(futureKey));
      expect(futureInk.onTap, isNull);
    }

    // Pilih tanggal 1 bulan ini -> Terapkan
    final day1Key = Key('cal_day_${now.year}_${now.month}_1');
    await tester.tap(find.byKey(day1Key));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Custom Date (≤ 01 '), findsOneWidget);

    // Uji Custom Date Range lintas tahun: 1 Desember 2004 -> 17 Maret 2006
    await tester.tap(find.text('Custom Date Range'));
    await tester.pumpAndSettle();

    // Pilih tahun 2004 dan bulan Desember -> klik tgl 1
    await tester.tap(find.byKey(const Key('calendar_year_dropdown')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('2004'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('2004').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2004').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_month_dropdown')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Desember'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Desember').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desember').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cal_day_2004_12_1')));
    await tester.pumpAndSettle();

    // Pilih tahun 2006 dan bulan Maret -> klik tgl 17
    await tester.tap(find.byKey(const Key('calendar_year_dropdown')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('2006'),
      -150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('2006').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2006').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_month_dropdown')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Maret'),
      -150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Maret').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maret').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cal_day_2006_3_17')));
    await tester.pumpAndSettle();

    expect(find.text('01 Des 2004'), findsOneWidget);
    expect(find.text('17 Mar 2006'), findsOneWidget);

    // Uji revisi interaktif: klik kotak Start Date -> otomatis lompat ke Des 2004 dan ubah ke 05 Des 2004 tanpa mereset End Date
    await tester.tap(find.byKey(const Key('range_start_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cal_day_2004_12_5')));
    await tester.pumpAndSettle();
    expect(find.text('05 Des 2004'), findsOneWidget);
    expect(find.text('17 Mar 2006'), findsOneWidget);

    // Klik kotak End Date -> otomatis lompat kembali ke Mar 2006 dan ubah ke 20 Mar 2006
    await tester.tap(find.byKey(const Key('range_end_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cal_day_2006_3_20')));
    await tester.pumpAndSettle();
    expect(find.text('05 Des 2004'), findsOneWidget);
    expect(find.text('20 Mar 2006'), findsOneWidget);

    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();
    expect(
      find.text('Custom Date Range (05 Des 2004 – 20 Mar 2006)'),
      findsOneWidget,
    );
  });
}
