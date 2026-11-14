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
      expect(find.text('Sebelumnya'), findsWidgets);
      expect(find.text('Berikutnya'), findsWidgets);

      // Klik Berikutnya -> pindah ke Tab 2 (26–36)
      await tester.tap(find.text('Berikutnya').first);
      await tester.pumpAndSettle();
      expect(find.text('Tab 2 (26–36)'), findsWidgets);

      // 8. Buka menu titik 3 kartu video -> cek hanya ada 4 menu (Unsubscribe, Tonton di YouTube, Transkrip, Hide/Unhide) + popup transkrip
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsubscribe "'), findsOneWidget);
      expect(find.text('Tonton di YouTube'), findsOneWidget);
      expect(find.text('Transkrip'), findsOneWidget);
      expect(find.textContaining('Hide "'), findsOneWidget);
      expect(find.textContaining('Lihat Semua Video'), findsNothing);

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

      // Menu titik 3 tetap 6 item termasuk USB Sync
      await tester.tap(find.byTooltip('Menu Lainnya'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(6));
      expect(find.textContaining('USB'), findsOneWidget);
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

      // Navigasi Tab tetap muncul penuh meski cuma 1 halaman di dalam 1 creator
      expect(find.text('Navigasi Tab:'), findsOneWidget);
      expect(find.text('Sebelumnya'), findsOneWidget);
      expect(find.text('Tab 1 (1–6)'), findsOneWidget);
      expect(find.text('Berikutnya'), findsOneWidget);
      expect(find.text('Halaman 1 dari 1 (6 video)'), findsOneWidget);

      // Scrollbar Home Page juga tetap aktif di dalam tampilan 1 creator saat list overflow
      expect(find.byKey(const Key('home_fast_scrollbar')), findsOneWidget);
      expect(find.byKey(const Key('home_fast_thumb')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Live Streaming: posisi di bawah Subscriptions & Navigasi Tab, update saat Refresh & auto-refresh saat buka/kembali ke aplikasi/Following',
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

          // Auto-refresh saat membuka aplikasi terpanggil 1x & memunculkan channel live
          expect(refreshCalls, 1);
          expect(find.byKey(const Key('sidebar_live_section')), findsOneWidget);
          expect(find.byKey(const Key('main_live_section')), findsOneWidget);
          expect(find.text('Live Streaming (1)'), findsNWidgets(2));
          expect(find.byKey(const Key('sidebar_live_item_UC_demo_fajrul')), findsOneWidget);
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsOneWidget);

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

          // Sebelum refresh baru, akun masih tampil live.
          // Pindah ke 1 creator lalu kembali ke Semua Follower -> auto-refresh berjalan & menghapus status live yang sudah selesai
          await tester.tap(find.text('MALAKA').first);
          await tester.pumpAndSettle();
          expect(find.text('Live Streaming (0)'), findsWidgets);

          // Tunggu lewat cooldown 4 detik lalu kembali ke Semua Follower
          await tester.pump(const Duration(seconds: 5));
          await tester.tap(find.textContaining('Semua Follower').first);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();

          expect(refreshCalls, 2);
          expect(find.byKey(const Key('sidebar_live_item_UC_demo_fajrul')), findsNothing);
          expect(find.byKey(const Key('main_live_item_UC_demo_fajrul')), findsNothing);
          expect(find.text('Live Streaming (0)'), findsNWidgets(2));

          // Simulasikan keluar dari aplikasi (inactive->hidden->paused) lalu masuk kembali (hidden->inactive->resumed) -> auto-refresh berjalan lagi
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();
          expect(refreshCalls, 3);
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) => _TestBackendHttpClient(handleBackend),
      );
    },
  );
}

class _TestBackendHttpClient implements HttpClient {
  final Map<String, dynamic> Function(String method, Uri uri) handler;
  _TestBackendHttpClient(this.handler);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _TestHttpRequest(method, url, handler);

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
  final HttpHeaders _headers = _TestHttpHeaders();

  _TestHttpRequest(this.method, this.uri, this.handler);

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
    if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
      return _TestHttpResponse(404, '{}');
    }
    final body = jsonEncode(handler(method, uri));
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
