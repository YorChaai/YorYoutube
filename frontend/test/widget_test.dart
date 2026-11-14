import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets(
    'Audit UI: Dropdown Tab Navigation, Minimal Compact Mode, Refresh YouTube button, and Filters',
    (WidgetTester tester) async {
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
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const PersonalYouTubeApp());
      await tester.pumpAndSettle();
      expect(find.text('YouTube Follower'), findsOneWidget);

      // 1. Cek Sidebar Subscriptions tampil & toggle 2 mode (Penuh <-> Tersembunyi, tanpa mode mini)
      expect(find.text('Fajrul Fx'), findsWidgets);
      expect(find.text('Ferry Irwandi'), findsWidgets);
      expect(find.byIcon(Icons.keyboard_double_arrow_right), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_double_arrow_left), findsNothing);
      expect(find.byIcon(Icons.keyboard_double_arrow_right), findsNothing);
      expect(find.textContaining('Semua Follower ('), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_double_arrow_left), findsOneWidget);
      expect(find.textContaining('Semua Follower ('), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
      await tester.pumpAndSettle();
      expect(find.textContaining('Semua Follower ('), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.textContaining('Semua Follower ('), findsOneWidget);

      // 2. Cek tombol aksi header sekarang tampil sebagai logo saja (icon-only + tooltip)
      for (final tip in [
        'Sync Laptop (USB)',
        'Refresh YouTube',
        'Export Excel/CSV',
        'Tambah Channel',
      ]) {
        final btn = find.byTooltip(tip);
        expect(btn, findsOneWidget);
        expect(
          find.descendant(of: btn, matching: find.byType(Text)),
          findsNothing,
        );
      }
      expect(find.text('Sync Laptop (USB)'), findsNothing);
      expect(find.text('Sync HP (USB)'), findsNothing);
      expect(find.text('Refresh YouTube'), findsNothing);
      expect(find.text('Tambah Channel'), findsNothing);

      // 3. Cek Filter & Urutkan di sebelah kiri search bar compact + info filter ikut ter-hide saat scroll
      expect(find.text('Filter & Urutkan'), findsOneWidget);
      final filterRect = tester.getRect(find.text('Filter & Urutkan'));
      final searchFieldFinder = find.byType(TextField).first;
      final searchRect = tester.getRect(searchFieldFinder);
      expect(filterRect.right, lessThan(searchRect.left));
      expect(searchRect.width, lessThanOrEqualTo(360));
      expect(find.textContaining('Total: 36 video'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Filter & Urutkan'), findsOneWidget);
      expect(find.textContaining('Total: 36 video'), findsNothing);
      await tester.drag(find.byType(CustomScrollView).last, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('Total: 36 video'), findsOneWidget);

      // 3b. Cek 'Semua Follower' mempertahankan teks search, sedangkan tap logo 'Yor' / 'YouTube Follower' kembali ke All Follower + hapus teks search
      await tester.enterText(searchFieldFinder, 'AI');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fajrul Fx').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Semua Follower ('));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(searchFieldFinder).controller?.text,
        'AI',
      );
      expect(find.textContaining('Total: 36 video'), findsOneWidget);

      await tester.tap(find.text('Fajrul Fx').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yor'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(searchFieldFinder).controller?.text,
        isEmpty,
      );
      expect(find.textContaining('Total: 36 video'), findsOneWidget);

      await tester.enterText(searchFieldFinder, 'Musik');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fajrul Fx').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('YouTube Follower'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(searchFieldFinder).controller?.text,
        isEmpty,
      );
      expect(find.textContaining('Total: 36 video'), findsOneWidget);

      expect(find.textContaining('50 Video/Tab'), findsOneWidget);

      // Buka Pop-Up Filter dari bawah (gaya Android)
      await tester.tap(find.text('Filter & Urutkan'));
      await tester.pumpAndSettle();
      expect(find.text('Filter & Urutan Video'), findsOneWidget);
      expect(find.text('🔥 View Terbanyak'), findsOneWidget);
      expect(find.text('👍 Like Terbanyak'), findsOneWidget);
      expect(find.text('🕒 Terbaru ke Terlama'), findsOneWidget);
      expect(find.text('⏳ Terlama ke Terbaru'), findsOneWidget);
      expect(find.text('25 Video'), findsOneWidget);
      expect(find.text('50 Video'), findsOneWidget);
      expect(find.text('100 Video'), findsOneWidget);

      // Pastikan tombol '🔕 Unsubscribe' di bawah kartu video sudah dihapus (cukup lewat titik 3)
      expect(find.text('🔕 Unsubscribe'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsWidgets);

      // Pastikan filter waktu All Time, Today, This Week, This Month, This Year, Custom Date, Custom Date Range + Day tersedia di dalam pop-up
      expect(find.text('All Time'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('This Month'), findsOneWidget);
      expect(find.text('This Year'), findsOneWidget);
      expect(find.text('Custom Date'), findsOneWidget);
      expect(find.text('Custom Date Range'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
      final customRangeRect = tester.getRect(
        find.widgetWithText(ChoiceChip, 'Custom Date Range'),
      );
      final hariLaluRect = tester.getRect(find.byKey(const Key('hari_lalu_box')));
      expect((customRangeRect.height - hariLaluRect.height).abs(), lessThanOrEqualTo(0.5));

      // Pilih sementara '25 Video' untuk menguji navigasi Tab 1 <-> Tab 2, lalu tutup Pop-Up
      await tester.tap(find.text('25 Video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terapkan (Total 36 Video)'));
      await tester.pumpAndSettle();
      expect(find.text('Filter & Urutan Video'), findsNothing);

      expect(find.text('Tab 1 (1–25)'), findsWidgets);
      expect(find.byTooltip('Sebelumnya'), findsWidgets);
      expect(find.byTooltip('Berikutnya'), findsWidgets);

      // Klik Berikutnya (>) -> pindah ke Tab 2 (26–36)
      await tester.tap(find.byTooltip('Berikutnya').first);
      await tester.pumpAndSettle();
      expect(find.text('Tab 2 (26–36)'), findsWidgets);

      // 8. Buka menu titik 3 kartu video -> cek hanya ada 4 menu (Unsubscribe, Lihat Channel, Transkrip, Hide/Unhide) + popup transkrip
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsubscribe "'), findsOneWidget);
      expect(find.textContaining('Lihat Channel "'), findsOneWidget);
      expect(find.text('Tonton di YouTube'), findsNothing);
      expect(find.text('Transkrip'), findsOneWidget);
      expect(find.textContaining('Hide "'), findsOneWidget);
      expect(find.textContaining('Lihat Semua Video'), findsNothing);

      // Uji tap 'Lihat Channel "..."' -> membuka halaman channel tsb di dalam app & kembali ke Semua Follower
      await tester.tap(find.textContaining('Lihat Channel "'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Total: 6 video'), findsOneWidget);
      await tester.tap(find.textContaining('Semua Follower ('));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transkrip'));
      await tester.pumpAndSettle();
      expect(find.text('Transkrip + Prompt'), findsOneWidget);
      expect(find.text('Gunakan TubeTranscript.com'), findsOneWidget);
      expect(find.text('Kutip'), findsOneWidget);
      expect(find.text('Formal'), findsOneWidget);
      expect(find.text('2.0'), findsOneWidget);
      expect(find.text('3.0'), findsOneWidget);
      expect(find.byIcon(Icons.format_quote), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.byIcon(Icons.layers), findsOneWidget);

      // Aktifkan centang TubeTranscript lalu pilih prompt 2.0 -> masuk step Paste Transkrip
      await tester.tap(find.text('Gunakan TubeTranscript.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2.0'));
      await tester.pumpAndSettle();
      expect(
        find.text('Prompt "2.0" siap diisi dari TubeTranscript'),
        findsOneWidget,
      );
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
      expect(find.text('3.0'), findsOneWidget);
      expect(find.byIcon(Icons.format_quote), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.byIcon(Icons.layers), findsOneWidget);
      expect(find.text('Gunakan TubeTranscript.com'), findsOneWidget);
      expect(
        mockClipboard,
        contains('Ini contoh teks transkrip dari TubeTranscript.'),
      );

      // Uji 1-tap Paste Transkrip langsung dari Clipboard (tanpa ketik manual) dengan prompt Formal
      mockClipboard = 'Teks clipboard langsung dari TubeTranscript.';
      await tester.tap(find.text('Formal'));
      await tester.pumpAndSettle();
      expect(
        find.text('Prompt "Formal" siap diisi dari TubeTranscript'),
        findsOneWidget,
      );
      await tester.tap(find.text('Paste Transkrip'));
      await tester.pumpAndSettle();
      expect(
        find.text('Transkrip + Prompt Formal Siap (100%)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(
        mockClipboard,
        contains('Teks clipboard langsung dari TubeTranscript.'),
      );
      expect(find.text('Kutip'), findsOneWidget);
      expect(find.text('Gunakan TubeTranscript.com'), findsOneWidget);

      // Tutup popup dengan tombol silang (X) di kanan atas
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Transkrip + Prompt'), findsNothing);
    },
  );

  testWidgets(
    'Period Filters, Sorting (Newest/Oldest), Custom Date & Custom Date Range Calendar',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const PersonalYouTubeApp());
      await tester.pumpAndSettle();
      expect(find.text('YouTube Follower'), findsOneWidget);

      // Buka Pop-Up Filter gaya Android
      await tester.tap(find.text('Filter & Urutkan'));
      await tester.pumpAndSettle();

      // Uji pengurutan Terbaru <-> Terlama bersamaan dengan filter periode
      await tester.tap(find.text('⏳ Terlama ke Terbaru'));
      await tester.pumpAndSettle();
      expect(find.text('Terapkan (Total 36 Video)'), findsOneWidget);

      await tester.tap(find.text('This Year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Time'));
      await tester.pumpAndSettle();
      expect(find.text('Terapkan (Total 36 Video)'), findsOneWidget);

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
        final futureKey = Key(
          'cal_day_${now.year}_${now.month}_${now.day + 1}',
        );
        final futureInk = tester.widget<InkWell>(find.byKey(futureKey));
        expect(futureInk.onTap, isNull);
      }

      // Pilih tanggal 1 bulan ini -> Terapkan
      final day1Key = Key('cal_day_${now.year}_${now.month}_1');
      await tester.tap(find.byKey(day1Key));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terapkan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Custom Date (≤ 01 '), findsWidgets);

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
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'This Week'))
            .selected,
        isFalse,
      );

      // Pilih This Week -> harus memutus pilihan Custom Date Range (pilih salah satu)
      await tester.tap(find.text('This Week'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'This Week'))
            .selected,
        isTrue,
      );
      expect(find.text('Custom Date Range'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Custom Date Range'),
            )
            .selected,
        isFalse,
      );

      // Uji Day real-time: ketik '3' -> '30' langsung tampil & aktif tanpa perlu menekan Done/centang terlebih dahulu
      await tester.enterText(find.byKey(const Key('hari_lalu_input')), '3');
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'This Week'))
            .selected,
        isFalse,
      );
      final dayTf = tester.widget<TextField>(
        find.byKey(const Key('hari_lalu_input')),
      );
      expect(dayTf.focusNode!.hasFocus, isTrue);
      expect(dayTf.controller!.text, '3');

      await tester.enterText(find.byKey(const Key('hari_lalu_input')), '30');
      await tester.pump(const Duration(milliseconds: 250));
      expect(dayTf.focusNode!.hasFocus, isTrue);
      expect(dayTf.controller!.text, '30');
      expect(find.byKey(const Key('hari_lalu_clear')), findsOneWidget);
      expect(find.textContaining('30 Day'), findsWidgets);

      // Saat masih fokus mengedit (30 -> 28): tekan X mengosongkan teks tanpa kembali ke All Time & fokus tetap terbuka
      await tester.tap(find.byKey(const Key('hari_lalu_clear')));
      await tester.pump();
      expect(dayTf.controller!.text, isEmpty);
      expect(dayTf.focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All Time'))
            .selected,
        isFalse,
      );

      // Langsung ketik 28 real-time -> jadi 28 Day (mencakup hari 0..28 = 12 video)
      await tester.enterText(find.byKey(const Key('hari_lalu_input')), '28');
      await tester.pump(const Duration(milliseconds: 250));
      expect(dayTf.controller!.text, '28');
      expect(dayTf.focusNode!.hasFocus, isTrue);
      expect(find.textContaining('28 Day'), findsWidgets);
      expect(find.text('Terapkan (Total 12 Video)'), findsOneWidget);

      // Selesai centang (Done), lalu tekan tombol X saat tidak fokus -> langsung kembali ke All Time
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(dayTf.focusNode!.hasFocus, isFalse);
      await tester.tap(find.byKey(const Key('hari_lalu_clear')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All Time'))
            .selected,
        isTrue,
      );
      expect(find.byKey(const Key('hari_lalu_clear')), findsNothing);
      expect(find.text('Terapkan (Total 36 Video)'), findsOneWidget);

      // Uji angka 2 -> 2 Day mencakup hari 0..2 = 2 video
      await tester.enterText(find.byKey(const Key('hari_lalu_input')), '2');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('hari_lalu_clear')), findsOneWidget);
      expect(find.textContaining('2 Day'), findsWidgets);
      expect(find.text('Terapkan (Total 2 Video)'), findsOneWidget);

      // Done + klik X lagi -> kembali ke All Time
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hari_lalu_clear')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All Time'))
            .selected,
        isTrue,
      );
      expect(find.byKey(const Key('hari_lalu_clear')), findsNothing);
      expect(find.text('Terapkan (Total 36 Video)'), findsOneWidget);
    },
  );

  testWidgets(
    'Mobile 3 baris (Header pinned, Search bar hidden default, Filter info) + FAB biru polos scroll-to-top',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PersonalYouTubeApp());
      await tester.pumpAndSettle();

      // Line 1 Header tampil tanpa teks "YouTube Follower" (hanya Yor + Cari + Filter + Refresh + Menu 6 item)
      expect(find.text('YouTube Follower'), findsNothing);
      final headerTitleRect = tester.getRect(find.text('Yor'));
      expect(find.byIcon(Icons.usb), findsNothing);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);

      // Line 2 Search bar default tersembunyi (hidden)
      final searchFieldFinder = find.widgetWithText(TextField, 'Cari video...');
      expect(searchFieldFinder, findsNothing);

      // Line 3 Informasi filter & jumlah video tampil di bawah header
      final filterInfoFinder = find.textContaining('Total: 36 video');
      expect(filterInfoFinder, findsOneWidget);
      expect(
        tester.getRect(filterInfoFinder).top,
        greaterThan(headerTitleRect.bottom),
      );

      // Tampilkan Line 2 Search Bar lewat tombol cari di header
      await tester.tap(find.byKey(const Key('mobile_search_toggle')));
      await tester.pumpAndSettle();
      expect(searchFieldFinder, findsOneWidget);
      final searchRect = tester.getRect(searchFieldFinder);
      final filterInfoRectAfter = tester.getRect(filterInfoFinder);
      expect(searchRect.top, greaterThan(headerTitleRect.bottom));
      expect(filterInfoRectAfter.top, greaterThan(searchRect.bottom));

      // Menu titik 3 berisi 7 item termasuk USB Sync & Bersihkan Video Shorts
      await tester.tap(find.byTooltip('Menu Lainnya'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(7));
      expect(find.textContaining('USB'), findsOneWidget);
      expect(find.text('Bersihkan Video Shorts'), findsOneWidget);
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();

      // Scroll ke bawah -> Line 2 Search Bar & Line 3 Informasi Filter ter-hide, Header tetap pinned
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Yor'), findsOneWidget);
      expect(searchFieldFinder, findsNothing);
      expect(filterInfoFinder, findsNothing);

      // Floating button lingkaran kecil outline biru tipis transparan tanpa ikon/logo mengembalikan scroll ke atas
      final fabFinder = find.byKey(const Key('scroll_to_top_fab'));
      expect(fabFinder, findsOneWidget);
      final fabWidget = tester.widget<FloatingActionButton>(fabFinder);
      expect(fabWidget.backgroundColor, Colors.transparent);
      expect(fabWidget.shape, isA<CircleBorder>());
      final fabShape = fabWidget.shape as CircleBorder;
      expect(fabShape.side.color, const Color(0xFF2196F3));
      expect(fabShape.side.width, 2.0);
      expect(
        find.descendant(of: fabFinder, matching: find.byType(Icon)),
        findsNothing,
      );

      await tester.tap(fabFinder);
      await tester.pumpAndSettle();
      expect(searchFieldFinder, findsOneWidget);
      expect(filterInfoFinder, findsOneWidget);

      // Uji tombol silang (X): hanya mengosongkan teks tanpa loading, baru load saat tekan ikon kaca Search
      await tester.enterText(searchFieldFinder, 'Fajrul');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_submit_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cari: "Fajrul"'), findsOneWidget);
      expect(find.textContaining('Total: 36 video'), findsNothing);

      await tester.tap(find.byKey(const Key('search_clear_btn')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(searchFieldFinder).controller?.text,
        isEmpty,
      );
      expect(find.textContaining('Cari: "Fajrul"'), findsOneWidget);
      expect(find.textContaining('Total: 36 video'), findsNothing);

      await tester.tap(find.byKey(const Key('search_submit_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cari: "Fajrul"'), findsNothing);
      expect(find.textContaining('Total: 36 video'), findsOneWidget);

      // Uji scrollbar interaktif di Home Page (tekan track langsung loncat + hold-drag geser cepat)
      final homeRailFinder = find.byKey(const Key('home_fast_scrollbar'));
      expect(homeRailFinder, findsOneWidget);
      final homeThumbFinder = find.byKey(const Key('home_fast_thumb'));
      expect(homeThumbFinder, findsOneWidget);
      final thumbTopBefore = tester.getTopLeft(homeThumbFinder).dy;
      final railRect = tester.getRect(homeRailFinder);
      await tester.tapAt(
        Offset(railRect.center.dx, railRect.top + railRect.height * 0.7),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(homeThumbFinder).dy,
        greaterThan(thumbTopBefore),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(homeThumbFinder),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, -180));
      await tester.pump();
      expect(find.textContaining('Video '), findsWidgets);
      await gesture.up();
      await tester.pumpAndSettle();

      // Pastikan pada layar mobile (390px) bottom sheet filter tidak overflow dan tinggi kotak sejajar 36px
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      final mRangeRect = tester.getRect(
        find.widgetWithText(ChoiceChip, 'Custom Date Range'),
      );
      final mDayRect = tester.getRect(find.byKey(const Key('hari_lalu_box')));
      expect((mRangeRect.height - mDayRect.height).abs(), lessThanOrEqualTo(0.5));
      if ((mRangeRect.top - mDayRect.top).abs() <= 1.0) {
        expect((mRangeRect.top - mDayRect.top).abs(), lessThanOrEqualTo(0.5));
        expect(
          (mRangeRect.bottom - mDayRect.bottom).abs(),
          lessThanOrEqualTo(0.5),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TabPickerDialog scrollbar interaktif: tekan track langsung loncat & hold-drag geser tab',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int? pickedPage;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  pickedPage = await showDialog<int>(
                    context: ctx,
                    builder: (_) => const TabPickerDialog(
                      totalPages: 200,
                      limit: 25,
                      totalVideos: 5000,
                      currentPage: 1,
                    ),
                  );
                },
                child: const Text('Buka Tab'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buka Tab'));
      await tester.pumpAndSettle();

      final trackFinder = find.byKey(const Key('tab_fast_scrollbar'));
      final thumbFinder = find.byKey(const Key('tab_fast_thumb'));
      expect(trackFinder, findsOneWidget);
      expect(thumbFinder, findsOneWidget);
      expect(find.text('Tab 1 (1–25)'), findsOneWidget);
      expect(find.text('Tab 200 (4976–5000)'), findsNothing);

      // Tap di bagian bawah track saat thumb di atas -> langsung loncat ke bawah
      final trackRect = tester.getRect(trackFinder);
      await tester.tapAt(Offset(trackRect.center.dx, trackRect.bottom - 8));
      await tester.pumpAndSettle();
      expect(find.text('Tab 200 (4976–5000)'), findsOneWidget);

      // Hold & geser thumb ke bagian tengah track -> berpindah ke sekitar pertengahan tab
      await tester.dragFrom(
        Offset(trackRect.center.dx, trackRect.bottom - 10),
        Offset(0, -(trackRect.height / 2)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tab 1 (1–25)'), findsNothing);
      expect(find.text('Tab 200 (4976–5000)'), findsNothing);

      // Hold & geser sampai atas -> Tab 1 kembali tampil & bisa dipilih
      await tester.dragFrom(
        trackRect.center,
        Offset(0, -trackRect.height),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tab 1 (1–25)'), findsOneWidget);

      await tester.tap(find.text('Tab 1 (1–25)'));
      await tester.pumpAndSettle();
      expect(pickedPage, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Filter Hide/Unhide/Both menggantikan Wilayah Konten, simbol H kuning, & tahan 1 detik tanpa konfirmasi',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PersonalYouTubeApp());
      await tester.pumpAndSettle();

      // Default selalu Unhide
      expect(find.textContaining('👁️ Unhide'), findsOneWidget);
      expect(find.text('Semua Follower (6)'), findsOneWidget);
      expect(find.textContaining('Total: 36 video'), findsOneWidget);
      expect(find.text('H'), findsNothing);

      // Pastikan Filter Modal mengganti Wilayah Konten menjadi All, Unhide / Hide (2 baris)
      await tester.tap(find.text('Filter & Urutkan'));
      await tester.pumpAndSettle();
      expect(find.text('Wilayah Konten:'), findsNothing);
      expect(find.text('Nasional'), findsNothing);
      expect(find.text('Internasional'), findsNothing);
      expect(find.text('Channel Hide / Normal:'), findsOneWidget);

      final allChip = find.widgetWithText(ChoiceChip, 'All');
      final unhideChip = find.widgetWithText(ChoiceChip, 'Unhide');
      final hideChip = find.widgetWithText(ChoiceChip, 'Hide');
      expect(allChip, findsOneWidget);
      expect(unhideChip, findsOneWidget);
      expect(hideChip, findsOneWidget);

      final allRect = tester.getRect(allChip);
      final unhideRect = tester.getRect(unhideChip);
      final hideRect = tester.getRect(hideChip);
      expect((allRect.top - unhideRect.top).abs(), lessThan(4.0));
      expect(allRect.left, lessThan(unhideRect.left));
      expect(hideRect.top, greaterThan(allRect.bottom));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tahan 1 detik tombol Hide di menu titik 3 video pertama -> langsung Hide tanpa dialog konfirmasi
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      final hideMenuItem = find.textContaining('Hide "').first;
      final gesture = await tester.startGesture(tester.getCenter(hideMenuItem));
      await tester.pump(const Duration(milliseconds: 1150));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('yakin'), findsNothing);
      expect(find.text('Semua Follower (5)'), findsOneWidget);
      expect(find.textContaining('Total: 30 video'), findsOneWidget);

      // Buka filter -> pilih Hide -> tampilkan channel yang tersembunyi beserta simbol H kuning
      await tester.tap(find.text('Filter & Urutkan'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hide'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Semua Follower (1)'), findsOneWidget);
      expect(find.textContaining('Total: 6 video'), findsOneWidget);
      expect(find.text('H'), findsWidgets);

      // Buka filter -> pilih All -> semua tampil, yang di-hide punya simbol H kuning
      await tester.tap(find.text('Filter & Urutkan'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('👁️ All'), findsOneWidget);
      expect(find.text('Semua Follower (6)'), findsOneWidget);
      expect(find.textContaining('Total: 36 video'), findsOneWidget);
      expect(find.text('H'), findsWidgets);

      // Tahan 1 detik tombol Unhide di menu titik 3 -> langsung Unhide tanpa konfirmasi
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      final unhideMenuItem = find.textContaining('Unhide "').first;
      final gesture2 = await tester.startGesture(
        tester.getCenter(unhideMenuItem),
      );
      await tester.pump(const Duration(milliseconds: 1150));
      await gesture2.up();
      await tester.pumpAndSettle();

      expect(find.text('H'), findsNothing);
      expect(find.text('Semua Follower (6)'), findsOneWidget);
      expect(find.textContaining('Total: 36 video'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Follower sidebar scrollbar interaktif & Navigasi Tab + scrollbar tampil di 1 creator',
    (WidgetTester tester) async {
      // Tinggi viewport 360px membuat daftar channel sidebar overflow -> sidebar_fast_scrollbar aktif
      tester.view.physicalSize = const Size(1280, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PersonalYouTubeApp());
      await tester.pumpAndSettle();

      final sidebarRail = find.byKey(const Key('sidebar_fast_scrollbar'));
      final sidebarThumb = find.byKey(const Key('sidebar_fast_thumb'));
      expect(sidebarRail, findsOneWidget);
      expect(sidebarThumb, findsOneWidget);

      final thumbTopBefore = tester.getTopLeft(sidebarThumb).dy;
      final railRect = tester.getRect(sidebarRail);
      await tester.tapAt(
        Offset(railRect.center.dx, railRect.top + railRect.height * 0.8),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(sidebarThumb).dy,
        greaterThan(thumbTopBefore),
      );

      final gesture = await tester.startGesture(tester.getCenter(sidebarThumb));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(find.textContaining('Channel '), findsWidgets);
      await gesture.up();
      await tester.pumpAndSettle();

      // Pilih 1 creator ('Fajrul Fx', 6 video < limit 50) di mobile 390x600
      tester.view.physicalSize = const Size(390, 600);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fajrul Fx').first);
      await tester.pumpAndSettle();

      // Navigasi Tab ringkas 1 baris (<, Tab 1 (1–6), >) tetap muncul di dalam 1 creator
      expect(find.text('Nav Tab :'), findsOneWidget);
      expect(find.byKey(const Key('tab_prev_btn')), findsOneWidget);
      expect(find.text('Tab 1 (1–6)'), findsOneWidget);
      expect(find.byKey(const Key('tab_next_btn')), findsOneWidget);
      expect(find.text('Halaman 1 dari 1 (6 video)'), findsOneWidget);

      // Pastikan Nav Tab :, <, Tab 1 (1–6), dan > sejajar 1 baris di lebar mobile 390px
      final navTabRect = tester.getRect(find.text('Nav Tab :'));
      final prevRect = tester.getRect(find.byKey(const Key('tab_prev_btn')));
      final tabBtnRect = tester.getRect(find.byKey(const Key('tab_selector_btn')));
      final nextRect = tester.getRect(find.byKey(const Key('tab_next_btn')));
      expect((navTabRect.center.dy - prevRect.center.dy).abs(), lessThan(4.0));
      expect((prevRect.center.dy - tabBtnRect.center.dy).abs(), lessThan(4.0));
      expect((tabBtnRect.center.dy - nextRect.center.dy).abs(), lessThan(4.0));

      // Scrollbar Home Page juga tetap aktif di dalam tampilan 1 creator saat list overflow
      expect(find.byKey(const Key('home_fast_scrollbar')), findsOneWidget);
      expect(find.byKey(const Key('home_fast_thumb')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Live Streaming: posisi di bawah Subscriptions & Navigasi Tab, update saat Refresh manual & auto-refresh hanya 1x saat cold launch (tidak saat pindah halaman/background)',
    (WidgetTester tester) async {
      int refreshCalls = 0;
      bool liveActive = false;
      bool refreshDoneReady = false;

      final liveVideo = <String, dynamic>{
        'video_id': 'live_vid_99',
        'channel_id': 'UC_demo_fajrul',
        'channel_title': 'Fajrul Fx',
        'channel_thumbnail': '',
        'title': 'Live Eksperimen Sains!',
        'thumbnail_url': 'https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg',
        'published_at': DateTime.now().toUtc().toIso8601String(),
        'view_count': 123,
        'like_count': 45,
        'duration': '0:00',
        'duration_seconds': 0,
        'views_hp': 0,
        'views_laptop': 0,
        'views_total': 0,
        'watched_count': 0,
        'is_demo': 0,
        'is_live': 1,
      };
      final sampleChannels = [
        {
          'channel_id': 'UC_demo_fajrul',
          'title': 'Fajrul Fx',
          'handle': '@FajrulFx',
          'thumbnail_url': '',
          'uploads_playlist_id': 'UU_demo_fajrul',
          'source': 'demo',
          'video_count': 6,
          'watched_count': 0,
          'views_hp': 0,
          'views_laptop': 0,
          'views_total': 0,
          'is_hidden': 0,
          'status': 'subscribed',
        },
        {
          'channel_id': 'UC_demo_malaka',
          'title': 'MALAKA',
          'handle': '@malaka_project',
          'thumbnail_url': '',
          'uploads_playlist_id': 'UU_demo_malaka',
          'source': 'demo',
          'video_count': 6,
          'watched_count': 0,
          'views_hp': 0,
          'views_laptop': 0,
          'views_total': 0,
          'is_hidden': 0,
          'status': 'subscribed',
        },
      ];

      Map<String, dynamic> handleBackend(String method, Uri uri) {
        final path = uri.path;
        if (path == '/api/state') {
          return {
            'channels': sampleChannels,
            'live_streams': liveActive ? [liveVideo] : [],
            'has_api_key': true,
            'api_key_preview': 'AIzaSy...test',
            'has_oauth_token': false,
            'session_state': {'sort_by': 'time', 'period': 'all'},
            'default_limit': 50,
            'tab_limits': {},
            'active_limit': 50,
            'refresh_state': {
              'running': false,
              'done_ready': false,
              'progress': 0,
              'new_videos': 0,
            },
          };
        }
        if (path == '/api/videos') {
          final chFilter = uri.queryParameters['channel_id'] ?? '';
          final vids = liveActive
              ? [
                  {...liveVideo, 'title': 'Live Eksperimen Sains!'},
                  {...liveVideo, 'video_id': 'vod_1', 'title': 'Video Biasa', 'is_live': 0, 'duration': '10:00'},
                ]
              : [
                  {...liveVideo, 'video_id': 'vod_1', 'title': 'Video Biasa', 'is_live': 0, 'duration': '10:00'},
                ];
          final filtered = chFilter.isEmpty
              ? vids
              : vids.where((v) => v['channel_id'] == chFilter).toList();
          final liveFiltered = liveActive && (chFilter.isEmpty || chFilter == 'UC_demo_fajrul')
              ? [liveVideo]
              : [];
          return {
            'items': filtered,
            'total': filtered.length,
            'page': 1,
            'limit': 50,
            'total_pages': 1,
            'live_streams': liveFiltered,
          };
        }
        if (path == '/api/refresh-youtube' && method == 'POST') {
          refreshCalls++;
          // Refresh #1: turns live ON; Refresh #2+: turns live OFF (ended)
          liveActive = refreshCalls == 1;
          refreshDoneReady = true;
          return {'status': 'started', 'running': true, 'progress': 5};
        }
        if (path == '/api/refresh-youtube/status') {
          return {
            'running': false,
            'progress': 100,
            'done_ready': refreshDoneReady,
            'new_videos': refreshCalls == 1 ? 1 : 0,
            'error': '',
          };
        }
        if (path == '/api/refresh-youtube/consume' && method == 'POST') {
          refreshDoneReady = false;
          return {'status': 'ok'};
        }
        return {'status': 'ok'};
      }

      await HttpOverrides.runZoned(
        () async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(const PersonalYouTubeApp());
          await tester.pumpAndSettle();
          // Polling timer runs at 600ms
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();

          // Auto-refresh saat membuka aplikasi terpanggil 1x & header Live Streaming (1) default collapse (>)
          expect(refreshCalls, 1);
          expect(find.byKey(const Key('sidebar_live_section')), findsOneWidget);
          expect(find.byKey(const Key('main_live_section')), findsOneWidget);
          expect(find.text('Live Streaming (1)'), findsNWidgets(2));
          expect(find.byIcon(Icons.keyboard_arrow_right), findsNWidgets(2));
          expect(find.byKey(const Key('sidebar_live_item_UC_demo_fajrul')), findsNothing);
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsNothing);

          // Tekan toggle '>' menjadi 'v' untuk menampilkan daftar live streaming (dan tap lagi untuk tutup)
          await tester.tap(find.byKey(const Key('sidebar_live_toggle')));
          await tester.tap(find.byKey(const Key('main_live_toggle')));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(2));
          expect(find.byKey(const Key('sidebar_live_item_UC_demo_fajrul')), findsOneWidget);
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsOneWidget);

          // Tekan lagi toggle main -> kembali collapse '>'
          await tester.tap(find.byKey(const Key('main_live_toggle')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsNothing);
          // Expand kembali main agar bisa mengecek item di langkah selanjutnya
          await tester.tap(find.byKey(const Key('main_live_toggle')));
          await tester.pumpAndSettle();

          // Verifikasi posisi Sidebar: Subscriptions -> Live Streaming -> Daftar Follower
          final subsRect = tester.getRect(find.text('Subscriptions ›'));
          final sideLiveRect = tester.getRect(
            find.byKey(const Key('sidebar_live_section')),
          );
          final firstFollowerRect = tester.getRect(find.text('MALAKA').first);
          expect(sideLiveRect.top, greaterThanOrEqualTo(subsRect.bottom - 1));
          expect(firstFollowerRect.top, greaterThanOrEqualTo(sideLiveRect.bottom - 1));

          // Verifikasi posisi Main Page: Navigasi Tab / Halaman ... -> Live Streaming
          final halamanRect = tester.getRect(
            find.textContaining('Halaman 1 dari 1').first,
          );
          final mainLiveRect = tester.getRect(
            find.byKey(const Key('main_live_section')),
          );
          expect(mainLiveRect.top, greaterThanOrEqualTo(halamanRect.bottom - 1));

          // Sebelum refresh manual, akun masih tampil live.
          // Pindah ke 1 creator lalu kembali ke Semua Follower -> TIDAK memicu auto-refresh
          await tester.tap(find.text('MALAKA').first);
          await tester.pumpAndSettle();
          expect(find.text('Live Streaming (0)'), findsWidgets);

          await tester.pump(const Duration(seconds: 5));
          await tester.tap(find.textContaining('Semua Follower').first);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();

          expect(refreshCalls, 1);
          expect(find.byKey(const Key('sidebar_live_item_UC_demo_fajrul')), findsOneWidget);
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsOneWidget);
          expect(find.text('Live Streaming (1)'), findsNWidgets(2));

          // Simulasikan keluar ke background / link YouTube (inactive->hidden->paused->resumed) -> TIDAK memicu auto-refresh
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();
          expect(refreshCalls, 1);

          // Klik tombol merah Refresh YouTube secara manual -> refresh berjalan & menghapus live yang sudah selesai
          await tester.tap(find.byTooltip('Refresh YouTube'));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();
          expect(refreshCalls, 2);
          expect(find.byKey(const Key('sidebar_live_item_UC_demo_fajrul')), findsNothing);
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsNothing);
          expect(find.text('Live Streaming (0)'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) => _TestBackendHttpClient(handleBackend),
      );
    },
  );

  testWidgets(
    'Standalone Mode parses UULV Atom <entry> <updated> after <published> and transitions 0:00 stream to LIVE',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var nowLive = false;
      final tenDaysAgoIso = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .toIso8601String();
      final freshUpdatedIso = DateTime.now().toUtc().toIso8601String();
      const cid = 'UCTestLiveChannel000001';
      const uulv = 'UULVTestLiveChannel000001';
      const vid = 'vid_upcoming_old';
      var uulvRssHits = 0;

      ({int statusCode, String body})? handleRaw(String method, Uri uri) {
        final host = uri.host;
        final path = uri.path;
        if (host == '127.0.0.1' ||
            host == 'localhost' ||
            host == '172.18.164.232' ||
            host == '192.168.68.54') {
          // Force Standalone Mode fallback
          return (statusCode: 404, body: '{}');
        }
        if (host == 'www.googleapis.com' && path == '/youtube/v3/channels') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'items': [
                {
                  'id': cid,
                  'snippet': {
                    'title': 'Ryzen Test Live',
                    'customUrl': '@RyzenTestLive',
                    'thumbnails': {
                      'default': {'url': 'https://i.ytimg.com/avatar.jpg'},
                    },
                  },
                  'contentDetails': {
                    'relatedPlaylists': {'uploads': 'UUTestLiveChannel000001'},
                  },
                },
              ],
            }),
          );
        }
        if (host == 'www.googleapis.com' &&
            path == '/youtube/v3/playlistItems') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'items': [
                {
                  'contentDetails': {'videoId': vid},
                },
              ],
            }),
          );
        }
        if (host == 'www.googleapis.com' && path == '/youtube/v3/videos') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'items': [
                {
                  'id': vid,
                  'snippet': {
                    'channelId': cid,
                    'channelTitle': 'Ryzen Test Live',
                    'title': 'Turnamen PUBG Mobile Live',
                    'publishedAt': nowLive ? freshUpdatedIso : tenDaysAgoIso,
                    'liveBroadcastContent': nowLive ? 'live' : 'none',
                    'thumbnails': {
                      'high': {'url': 'https://i.ytimg.com/vi/$vid/hqdefault.jpg'},
                    },
                  },
                  'statistics': {'viewCount': '1200', 'likeCount': '85'},
                  'contentDetails': {'duration': 'PT0S'},
                },
              ],
            }),
          );
        }
        if (host == 'www.youtube.com' && path == '/feeds/videos.xml') {
          final pid = uri.queryParameters['playlist_id'] ?? '';
          if (pid == uulv) {
            uulvRssHits += 1;
            return (
              statusCode: 200,
              body: '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015">
  <entry>
    <yt:videoId>$vid</yt:videoId>
    <title>Turnamen PUBG Mobile Live</title>
    <published>$tenDaysAgoIso</published>
    <updated>$freshUpdatedIso</updated>
  </entry>
</feed>''',
            );
          }
          return (
            statusCode: 200,
            body: '<?xml version="1.0" encoding="UTF-8"?><feed></feed>',
          );
        }
        return (statusCode: 404, body: '{}');
      }

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(const PersonalYouTubeApp());
          await tester.pumpAndSettle();

          // 1. Set API Key & clear server URL to ensure Standalone Mode
          await tester.tap(find.byTooltip('Pengaturan API & Sync'));
          await tester.pumpAndSettle();
          final dialogFields = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(dialogFields.at(0), 'AIzaTestStandaloneKey');
          await tester.enterText(dialogFields.at(2), '');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Simpan & Sync Sekarang'));
          await tester.pumpAndSettle();

          // 2. Add channel with a 10-day-old 0:00 upcoming stream (not live yet)
          await tester.tap(find.byTooltip('Tambah Channel'));
          await tester.pumpAndSettle();
          final addField = find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextField),
              )
              .first;
          await tester.enterText(addField, '@RyzenTestLive');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Tambah'));
          await tester.pumpAndSettle();

          expect(find.text('Live Streaming (1)'), findsNothing);

          // 3. Channel goes LIVE on YouTube -> hit Refresh YouTube in Standalone Mode
          nowLive = true;
          await tester.tap(find.byTooltip('Refresh YouTube'));
          await tester.pumpAndSettle();

          expect(uulvRssHits, greaterThanOrEqualTo(1));
          expect(find.text('Live Streaming (1)'), findsNWidgets(2));
          expect(find.text('Ryzen Test Live'), findsWidgets);
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) =>
            _TestBackendHttpClient((_, _) => {}, rawHandler: handleRaw),
      );
    },
  );

  testWidgets(
    'Sidebar Subscriptions minimize toggle, main search creator card, and creator 3-dot Reload & Custom Range modal work',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var reloadHits = 0;
      Completer<void>? reloadGate;
      Future<Map<String, dynamic>> handleBackend(String method, Uri uri) async {
        final path = uri.path;
        if (path == '/api/state') {
          return {
            'status': 'ok',
            'has_api_key': false,
            'api_key_preview': '',
            'default_limit': 50,
            'tab_limits': {},
            'live_streams': const [],
            'channels': [
              {
                'channel_id': 'UC_ferry',
                'title': 'Ferry Irwandi',
                'handle': '@ferryirwandi',
                'thumbnail_url': '',
                'watched_count': 4,
                'views_hp': 2,
                'views_laptop': 2,
                'views_total': 4,
                'synced_video_count': 2,
                'yt_video_count': 450,
                'yt_subscriber_count': 2440000,
                'is_hidden': 0,
              },
              {
                'channel_id': 'UC_pew',
                'title': 'PewDiePie',
                'handle': '@PewDiePie',
                'thumbnail_url': '',
                'watched_count': 2,
                'views_hp': 1,
                'views_laptop': 1,
                'views_total': 2,
                'synced_video_count': 1,
                'yt_video_count': 4700,
                'yt_subscriber_count': 111000000,
                'is_hidden': 0,
              },
            ],
            'ui_state': {'sort_by': 'time', 'period': 'all', 'limit': 50},
          };
        }
        if (path == '/api/videos') {
          final q = (uri.queryParameters['q'] ?? '').toLowerCase();
          final allItems = [
            {
              'video_id': 'vid_ferry_1',
              'channel_id': 'UC_ferry',
              'channel_title': 'Ferry Irwandi',
              'channel_thumbnail': '',
              'title': 'Membahas Ekonomi Indonesia',
              'thumbnail_url': '',
              'published_at': '2026-11-10T10:00:00Z',
              'view_count': 395000,
              'like_count': 25000,
              'duration': '31:10',
              'duration_seconds': 1870,
              'views_hp': 1,
              'views_laptop': 1,
              'views_total': 2,
              'watched_count': 4,
              'is_hidden': 0,
              'is_live': 0,
            },
            {
              'video_id': 'vid_pew_1',
              'channel_id': 'UC_pew',
              'channel_title': 'PewDiePie',
              'channel_thumbnail': '',
              'title': 'Minecraft Episode 1',
              'thumbnail_url': '',
              'published_at': '2026-11-09T10:00:00Z',
              'view_count': 2000000,
              'like_count': 150000,
              'duration': '20:00',
              'duration_seconds': 1200,
              'views_hp': 0,
              'views_laptop': 0,
              'views_total': 0,
              'watched_count': 2,
              'is_hidden': 0,
              'is_live': 0,
            },
          ];
          final filtered = q.isEmpty
              ? allItems
              : allItems
                    .where(
                      (v) =>
                          v['title'].toString().toLowerCase().contains(q) ||
                          v['channel_title'].toString().toLowerCase().contains(q),
                    )
                    .toList();
          return {
            'status': 'ok',
            'total': filtered.length,
            'page': 1,
            'limit': 50,
            'total_pages': 1,
            'items': filtered,
            'live_streams': const [],
          };
        }
        if (path == '/api/channels/UC_ferry/reload-status' && method == 'GET') {
          return {
            'running': reloadGate != null && !reloadGate!.isCompleted,
            'progress': 65,
            'error': '',
          };
        }
        if (path == '/api/channels/UC_ferry/reload' && method == 'POST') {
          reloadHits += 1;
          if (reloadGate != null) {
            await reloadGate!.future;
          }
          return {
            'status': 'ok',
            'channel_id': 'UC_ferry',
            'videos_synced': 100,
            'total_channel_videos': 102,
          };
        }
        if (path == '/api/refresh-youtube/status') {
          return {
            'running': false,
            'progress': 0,
            'done_ready': false,
            'new_videos': 0,
            'error': '',
          };
        }
        if (path == '/api/refresh-youtube') {
          return {'status': 'started', 'running': false, 'progress': 0};
        }
        return {'status': 'ok'};
      }

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(const PersonalYouTubeApp());
          await tester.pumpAndSettle();

          // 1. Sidebar collapse/expand Subscriptions
          expect(find.byKey(const Key('sidebar_subscriptions_toggle')), findsOneWidget);
          expect(find.text('PewDiePie'), findsWidgets);
          await tester.tap(find.byKey(const Key('sidebar_subscriptions_toggle')));
          await tester.pumpAndSettle();
          // Expand again and confirm it works cleanly
          await tester.tap(find.byKey(const Key('sidebar_subscriptions_toggle')));
          await tester.pumpAndSettle();

          // 2. Type 'ferry' in main search -> shows matching Creator Card at top
          final searchField = find.byType(TextField).first;
          await tester.enterText(searchField, 'ferry');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byKey(const Key('search_creator_card_UC_ferry')), findsOneWidget);
          expect(find.text('Subscribed'), findsOneWidget);

          // 3. Open 3-dot Creator Menu -> Custom Date Range, Unsubscribe, Hide (no Reload Data Channel)
          await tester.tap(find.byKey(const Key('creator_menu_btn_UC_ferry')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Reload Data Channel'), findsNothing);
          expect(find.text('Atur Tanggal & Batas Video'), findsOneWidget);
          expect(find.text('Unsubscribe "Ferry Irwandi"'), findsOneWidget);
          expect(find.text('Hide "Ferry Irwandi"'), findsOneWidget);

          // 4. Open Custom Date Range modal -> check years (1, 5, 10, X Tahun) & limits (10..10000)
          await tester.tap(find.text('Atur Tanggal & Batas Video'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const Key('creator_range_picker_btn_UC_ferry')), findsOneWidget);
          expect(find.text('1 Bulan Ini'), findsNothing);
          expect(find.text('6 Bulan'), findsNothing);
          expect(find.text('1 Tahun'), findsOneWidget);
          expect(find.text('5 Tahun'), findsOneWidget);
          expect(find.text('10 Tahun'), findsOneWidget);
          expect(find.byKey(const Key('tahun_lalu_box')), findsOneWidget);

          // Test custom X year box
          await tester.enterText(find.byKey(const Key('tahun_lalu_input')), '3');
          await tester.pump();
          final expectedStartYear = '${DateTime.now().year - 3}-';
          expect(find.textContaining(expectedStartYear), findsOneWidget);

          // Check video caps: 10, 500, 1000, 5000, 10000
          expect(find.text('10 video'), findsOneWidget);
          expect(find.text('500 video'), findsOneWidget);
          expect(find.text('1000 video'), findsOneWidget);
          expect(find.text('5000 video'), findsOneWidget);
          expect(find.text('10000 video'), findsOneWidget);
          await tester.tap(find.text('5000 video'));
          await tester.pump();
          expect(find.text('Reload (5000 video)'), findsOneWidget);

          reloadGate = Completer<void>();
          await tester.tap(find.byKey(const Key('creator_range_submit_btn_UC_ferry')));
          await tester.pump();
          // Initial progress badge appears (red circular percentage indicator)
          expect(find.byKey(const Key('creator_reload_progress_UC_ferry')), findsOneWidget);
          // Poll interval (350ms) fetches 65% from /reload-status
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('65%'), findsOneWidget);

          reloadGate!.complete();
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('creator_reload_progress_UC_ferry')), findsNothing);
          expect(reloadHits, equals(1));
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) =>
            _TestBackendHttpClient((_, _) => {}, asyncHandler: handleBackend),
      );
    },
  );

  testWidgets(
    'Back from Creator returns to Semua Follower, and Back from Home shows Exit popup with top-right close button',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final requestedChannelIds = <String>[];
      Map<String, dynamic> handleBackend(String method, Uri uri) {
        if (uri.path == '/api/state') {
          return {
            'status': 'ok',
            'has_api_key': true,
            'channels': [
              {
                'channel_id': 'UC_ferry',
                'title': 'Ferry Irwandi',
                'handle': '@FerryIrwandi',
                'thumbnail_url': '',
                'watched_count': 5,
                'views_hp': 2,
                'views_laptop': 3,
                'views_total': 5,
                'is_hidden': 0,
              },
            ],
            'live_streams': [],
            'session_state': {'channel_id': 'UC_ferry'},
            'refresh_state': {'running': false},
          };
        }
        if (uri.path == '/api/videos') {
          requestedChannelIds.add(uri.queryParameters['channel_id'] ?? '');
          return {
            'items': [],
            'total': 0,
            'page': 1,
            'total_pages': 1,
          };
        }
        return {'status': 'ok'};
      }

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(const PersonalYouTubeApp());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Initially inside Creator 'UC_ferry' -> Back must return to Semua Follower (''), NO exit dialog
          expect(requestedChannelIds.last, equals('UC_ferry'));
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(requestedChannelIds.last, equals(''));
          expect(find.byKey(const Key('exit_confirm_dialog')), findsNothing);

          // Now at Semua Follower ('') -> Back opens Exit confirmation dialog
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const Key('exit_confirm_dialog')), findsOneWidget);
          expect(find.byKey(const Key('exit_dialog_close_btn')), findsOneWidget);
          expect(find.byKey(const Key('exit_dialog_confirm_btn')), findsOneWidget);

          // Tapping top-right X cancels and stays in app
          await tester.tap(find.byKey(const Key('exit_dialog_close_btn')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const Key('exit_confirm_dialog')), findsNothing);
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) => _TestBackendHttpClient(handleBackend),
      );
    },
  );

  testWidgets(
    'Sync USB HP mempertahankan Hide dengan timestamp lebih baru & Desktop memanggil /api/sync/usb-prepare',
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.windows}),
    (WidgetTester tester) async {
      // 1. Desktop (Windows): tombol Sync USB memanggil /api/sync/usb-prepare, bukan /api/sync/exchange ke diri sendiri
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int prepareCalls = 0;
      int exchangeCalls = 0;

      Map<String, dynamic> handleDesktop(String method, Uri uri) {
        if (uri.path == '/api/state') {
          return {
            'channels': [
              {
                'channel_id': 'UC_demo_fajrul',
                'title': 'Fajrul Fx',
                'handle': '@FajrulFx',
                'thumbnail_url': '',
                'watched_count': 0,
                'views_hp': 0,
                'views_laptop': 0,
                'views_total': 0,
                'is_hidden': 0,
                'hidden_updated_at': '',
              },
            ],
            'live_streams': [],
            'has_api_key': false,
            'session_state': {},
            'refresh_state': {'running': false},
          };
        }
        if (uri.path == '/api/videos') {
          return {'items': [], 'total': 0, 'page': 1, 'total_pages': 1};
        }
        if (uri.path == '/api/sync/usb-prepare') {
          prepareCalls++;
          return {
            'connected': true,
            'devices': ['DEIVYTAMMJNJPR85'],
            'reverse_ok': true,
            'error': '',
          };
        }
        if (uri.path == '/api/sync/exchange') {
          exchangeCalls++;
          return {'videos': [], 'channels': []};
        }
        return {'status': 'ok'};
      }

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(const PersonalYouTubeApp());
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Sync HP (USB)'));
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();

          expect(prepareCalls, equals(1));
          expect(exchangeCalls, equals(0));
          expect(find.textContaining('port 8000 siap'), findsOneWidget);
        },
        createHttpClient: (_) => _TestBackendHttpClient(handleDesktop),
      );

      // 2. Unit verifikasi rekonsiliasi status Hide/Unhide saat Sync USB & Import JSON
      // A: HP Hide (timestamp baru) vs Laptop Unhide kosong -> tetap Hide
      final localWithTimestamp = <String, dynamic>{
        'channel_id': 'UC_luxxy',
        'is_hidden': 1,
        'hidden_updated_at': '2026-11-14T16:50:00Z',
      };
      reconcileChannelHideState(localWithTimestamp, {
        'channel_id': 'UC_luxxy',
        'is_hidden': 0,
        'hidden_updated_at': '',
      });
      expect(localWithTimestamp['is_hidden'], equals(1));
      expect(
        localWithTimestamp['hidden_updated_at'],
        equals('2026-11-14T16:50:00Z'),
      );

      // B: HP Unhide (timestamp lama) vs Laptop Hide (timestamp baru) -> ikut Hide
      final localFollowsRemoteHide = <String, dynamic>{
        'channel_id': 'UC_malaka',
        'is_hidden': 0,
        'hidden_updated_at': '2026-11-14T10:00:00Z',
      };
      reconcileChannelHideState(localFollowsRemoteHide, {
        'channel_id': 'UC_malaka',
        'is_hidden': 1,
        'hidden_updated_at': '2026-11-14T16:51:00Z',
      });
      expect(localFollowsRemoteHide['is_hidden'], equals(1));
      expect(
        localFollowsRemoteHide['hidden_updated_at'],
        equals('2026-11-14T16:51:00Z'),
      );

      // C: Legacy kosong di kedua sisi -> Hide eksplisit dipertahankan vs Unhide default
      final localLegacyUnhide = <String, dynamic>{
        'channel_id': 'UC_legacy',
        'is_hidden': 0,
        'hidden_updated_at': '',
      };
      reconcileChannelHideState(localLegacyUnhide, {
        'channel_id': 'UC_legacy',
        'is_hidden': 1,
        'hidden_updated_at': '',
      });
      expect(localLegacyUnhide['is_hidden'], equals(1));

      // D: Explicit Unhide ber-timestamp mengalahkan legacy Hide kosong
      final localLegacyHide = <String, dynamic>{
        'channel_id': 'UC_legacy_unhide',
        'is_hidden': 1,
        'hidden_updated_at': '',
      };
      reconcileChannelHideState(localLegacyHide, {
        'channel_id': 'UC_legacy_unhide',
        'is_hidden': 0,
        'hidden_updated_at': '2026-11-14T16:55:00Z',
      });
      expect(localLegacyHide['is_hidden'], equals(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tooltip sidebar creator tertutup maksimal 5 detik dan langsung hilang saat sidebar di-scroll',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PersonalYouTubeApp());
      await tester.pumpAndSettle();

      // Long press item creator pertama di sidebar memunculkan tooltip info views
      await tester.longPress(find.text('Fajrul Fx').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Total: 0 view (📱 HP:'), findsOneWidget);

      // Scroll sidebar ke bawah -> tooltip langsung hilang seketika
      await tester.drag(
        find.byKey(const Key('sidebar_fast_scrollbar')),
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Total: 0 view (📱 HP:'), findsNothing);

      // Kembalikan ke atas lalu munculkan lagi & biarkan selama 5 detik -> tooltip otomatis hilang
      await tester.drag(
        find.byKey(const Key('sidebar_fast_scrollbar')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Fajrul Fx').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Total: 0 view (📱 HP:'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('Total: 0 view (📱 HP:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TestBackendHttpClient implements HttpClient {
  final Map<String, dynamic> Function(String method, Uri uri) handler;
  final Future<Map<String, dynamic>> Function(String method, Uri uri)?
      asyncHandler;
  final ({int statusCode, String body})? Function(String method, Uri uri)?
      rawHandler;
  _TestBackendHttpClient(this.handler, {this.rawHandler, this.asyncHandler});

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _TestHttpRequest(
        method,
        url,
        handler,
        rawHandler: rawHandler,
        asyncHandler: asyncHandler,
      );

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestHttpRequest implements HttpClientRequest {
  @override
  final String method;
  @override
  final Uri uri;
  final Map<String, dynamic> Function(String method, Uri uri) handler;
  final Future<Map<String, dynamic>> Function(String method, Uri uri)?
      asyncHandler;
  final ({int statusCode, String body})? Function(String method, Uri uri)?
      rawHandler;
  final HttpHeaders _headers = _TestHttpHeaders();

  _TestHttpRequest(
    this.method,
    this.uri,
    this.handler, {
    this.rawHandler,
    this.asyncHandler,
  });

  @override
  HttpHeaders get headers => _headers;

  @override
  Encoding encoding = utf8;

  @override
  bool bufferOutput = true;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain();

  @override
  Future<HttpClientResponse> close() async {
    if (rawHandler != null) {
      final raw = rawHandler!(method, uri);
      if (raw != null) {
        return _TestHttpResponse(raw.statusCode, raw.body);
      }
    }
    if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
      return _TestHttpResponse(404, '{}');
    }
    final payload = asyncHandler != null
        ? await asyncHandler!(method, uri)
        : handler(method, uri);
    final body = jsonEncode(payload);
    return _TestHttpResponse(200, body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestHttpResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> _bytes;
  final HttpHeaders _headers = _TestHttpHeaders();

  _TestHttpResponse(this.statusCode, String body) : _bytes = utf8.encode(body);

  @override
  int get contentLength => _bytes.length;

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => true;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpHeaders get headers => _headers;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {
    action('content-type', ['application/json; charset=utf-8']);
  }

  @override
  String? value(String name) =>
      name.toLowerCase() == 'content-type' ? 'application/json; charset=utf-8' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
