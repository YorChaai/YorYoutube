import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const PersonalYouTubeApp());
}

class PersonalYouTubeApp extends StatelessWidget {
  const PersonalYouTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal YouTube Subscriptions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF303030),
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          actionTextColor: Colors.cyanAccent,
          behavior: SnackBarBehavior.floating,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF0033),
          surface: Color(0xFF212121),
        ),
      ),
      home: const YouTubeHomeScreen(),
    );
  }
}

class YouTubeHomeScreen extends StatefulWidget {
  const YouTubeHomeScreen({super.key});

  @override
  State<YouTubeHomeScreen> createState() => _YouTubeHomeScreenState();
}

class _YouTubeHomeScreenState extends State<YouTubeHomeScreen> {
  String baseUrl = Uri.base.port == 8000
      ? Uri.base.origin
      : 'http://127.0.0.1:8000';
  String sidebarMode = 'full'; // 'full' (240px) | 'hidden' (0px)
  bool filterMinimized =
      false; // Opsi meminimalkan bar urutan/filter agar area video lebih luas
  bool loading = false;
  bool refreshingYouTube = false;
  int refreshProgress = 0; // 0..100 persen
  bool refreshReadyGreen =
      false; // True jika 100% selesai sync dan tombol berubah HIJAU siap diklik
  int refreshNewVideosCount = 0;
  Timer? _refreshPollTimer;
  bool syncingUsb = false;
  int usbSyncProgress = 0; // 0..100 persen
  bool usbSyncReadyGreen = false;
  Timer? _usbSyncResetTimer;
  bool isStandaloneMode =
      false; // Otomatis aktif di HP jika tanpa backend Python
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Filter & Pagination State
  String sortBy = 'time'; // 'views' | 'likes' | 'time' | 'oldest'
  String period =
      'all'; // 'all' | 'today' | 'week' | 'month' | 'year' | '2d' | ... | 'custom_date' | 'custom_range'
  DateTime? customDate;
  DateTime? customRangeStart;
  DateTime? customRangeEnd;
  VoidCallback? _refreshFilterModal;
  String hideFilter =
      'unhide'; // 'unhide' | 'both' | 'hide' (selalu 'unhide' saat buka aplikasi)
  String selectedChannelId = '';
  String searchQuery = '';
  bool get _isHpDevice =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  String get _deviceType => _isHpDevice ? 'hp' : 'laptop';
  int limit = 50; // 25 | 50 | 100 (selalu mulai di 50 setiap buka aplikasi)
  int defaultLimit = 50;
  Map<String, int> tabLimits =
      {}; // Penyimpanan permanen jumlah video per tab/channel
  int currentPage = 1;
  int totalVideos = 0;
  int totalPages = 1;
  RangeValues durationRange = const RangeValues(
    0,
    120,
  ); // 0 menit s/d 120 menit (2 jam)
  Thumb? _activeDurationThumb;
  DateTime?
  skipUnsubscribeConfirmUntil; // Mode 10 menit langsung Unsubscribe tanpa konfirmasi

  List<Map<String, dynamic>> channels = [];
  List<Map<String, dynamic>> liveStreams = [];
  List<Map<String, dynamic>> videos = [];
  bool _didInitialAutoRefresh = false;
  bool hasApiKey = false;
  String apiKeyPreview = '';
  String localApiKey = '';
  String localOauthToken = '';
  String localMyChannelId = '';
  bool _bundledDataLoaded = false;
  final Set<String> _localUnsubscribedIds = {};

  // Database lokal mandiri di dalam aplikasi (untuk jalan sendiri di HP tanpa Python backend)
  final List<Map<String, dynamic>> _localChannels = [];
  final List<Map<String, dynamic>> _localVideos = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _dayInputCtrl = TextEditingController();
  final FocusNode _dayFocusNode = FocusNode();
  final GlobalKey _dayInputSlotKey = GlobalKey();
  Timer? _dayInputDebounce;
  VoidCallback? _activeDayFocusListener;
  final Map<String, int> _pubEpochCache = {};
  final FocusNode _mobileSearchFocusNode = FocusNode();
  final ScrollController _videoScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  bool _showMobileSearch = false;
  int _fetchVideosSeq = 0;

  @override
  void initState() {
    super.initState();
    _initLocalSeedData();
    _restoreSessionAndFetch();
  }

  @override
  void dispose() {
    _refreshPollTimer?.cancel();
    _usbSyncResetTimer?.cancel();
    _dayInputDebounce?.cancel();
    if (_activeDayFocusListener != null) {
      _dayFocusNode.removeListener(_activeDayFocusListener!);
      _activeDayFocusListener = null;
    }
    _searchCtrl.dispose();
    _dayInputCtrl.dispose();
    _dayFocusNode.dispose();
    _mobileSearchFocusNode.dispose();
    _videoScrollController.dispose();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  void _initLocalSeedData() {
    if (_localChannels.isNotEmpty) return;
    final now = DateTime.now().toUtc();
    final demoChannels = [
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        '@FajrulFx',
        'https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        '@AnimatedHistory',
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        '@malaka_project',
        'https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg',
      ),
      (
        'UC_demo_radit',
        'Raditya Dika',
        '@RadityaDika',
        'https://i.ytimg.com/vi/9bZkp7q19f0/hqdefault.jpg',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        '@JustinSung',
        'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
      ),
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        '@FerryIrwandi',
        'https://i.ytimg.com/vi/RgKAFK5djSk/hqdefault.jpg',
      ),
    ];
    for (final c in demoChannels) {
      _localChannels.add({
        'channel_id': c.$1,
        'title': c.$2,
        'handle': c.$3,
        'thumbnail_url': c.$4,
        'uploads_playlist_id': 'UU${c.$1.substring(2)}',
        'source': 'demo',
        'video_count': 6,
      });
    }

    const ytThumbs = [
      'dQw4w9WgXcQ',
      'M7lc1UVf-VE',
      'jNQXAC9IVRw',
      '9bZkp7q19f0',
      'kJQP7kiw5Fk',
      'RgKAFK5djSk',
      'OPf0YbXqDm0',
      'fJ9rUzIMcZQ',
      'CevxZvSJLk8',
      'JGwWNGJdvx8',
      'YQHsXMglC9A',
      'hT_nvWreIhg',
    ];

    final samples = [
      // Minggu ini (1 - 6 hari lalu)
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        'Kenapa Bank Terbesar di Paraguay Bisa Kolaps? - Kasus Ueno',
        1,
        512000,
        41200,
        '18:13',
      ),
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        'Apa yang Terjadi pada Tubuh Saat Makan Sekali Sehari (Jam demi Jam)',
        2,
        440000,
        32900,
        '10:18',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        'Cara Berpikir Kritis di Era Banjir Informasi (Minggu Ini)',
        3,
        690000,
        58100,
        '24:14',
      ),
      (
        'UC_demo_radit',
        'Raditya Dika',
        'Stand Up Comedy Spesial Minggu Ini: Cerita Finansial',
        4,
        920000,
        74500,
        '31:45',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        'How to Study 3x Faster Without Memorizing (This Week)',
        5,
        310000,
        27400,
        '16:20',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        'Sejarah Runtuhnya Kekaisaran Romawi dalam 15 Menit',
        6,
        780000,
        63000,
        '15:08',
      ),
      // Bulan ini (9 - 27 hari lalu)
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        'Bedah Logika & Stoikisme Untuk Anak Muda (Bulan Ini)',
        9,
        830000,
        69300,
        '28:40',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        'Pendidikan & Masa Depan Kerja di Indonesia',
        12,
        1120000,
        94000,
        '42:10',
      ),
      (
        'UC_demo_radit',
        'Raditya Dika',
        'Podcast Cerita Horor Kantor Baru (Bulan Ini)',
        15,
        1450000,
        112000,
        '54:20',
      ),
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        'Eksperimen Sains: Tidur 4 Jam vs 8 Jam Selama Sebulan',
        19,
        610000,
        48700,
        '14:55',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        'Mind Mapping Technique for Deep Understanding',
        23,
        495000,
        39100,
        '21:12',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        'Perang Dunia II dari Sudut Pandang Ekonomi',
        27,
        950000,
        81200,
        '19:33',
      ),
      // Tahun ini (65 - 310 hari lalu)
      (
        'UC_demo_radit',
        'Raditya Dika',
        'Tur Rumah Baru & Studio Podcast (Tahun Ini)',
        65,
        2850000,
        198000,
        '38:15',
      ),
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        'Investigasi Fenomena Judi Online & Psikologi Bandar',
        110,
        3600000,
        285000,
        '35:48',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        'Monolog: Kenapa Kita Sering Merasa Tertinggal?',
        160,
        1940000,
        164000,
        '29:10',
      ),
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        'Fisika Kuantum Dijelaskan dengan Bahasa Tongkrongan',
        210,
        1150000,
        97500,
        '17:42',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        'Complete Guide to Self-Regulated Learning (This Year)',
        260,
        870000,
        71000,
        '26:05',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        'Kebangkitan dan Keruntuhan Majapahit (Animasi Lengkap)',
        310,
        2210000,
        175000,
        '33:20',
      ),
      // 2 Tahun Lalu (420 - 690 hari lalu)
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        'Revolusi Industri Kreatif & Konten (2 Tahun Lalu)',
        420,
        1420000,
        108000,
        '22:18',
      ),
      (
        'UC_demo_radit',
        'Raditya Dika',
        'Belajar Investasi dari Nol untuk Pemula (2 Tahun Lalu)',
        480,
        3100000,
        240000,
        '41:00',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        'Episode Perdana: Membangun Manusia Merdeka (2 Tahun Lalu)',
        530,
        2540000,
        215000,
        '47:30',
      ),
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        'Sejarah Penemuan Listrik & Konflik Tesla vs Edison',
        590,
        980000,
        82400,
        '16:11',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        'Why Re-reading Notes Does Not Work (2 Years Ago)',
        640,
        1320000,
        104000,
        '15:45',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        'Peta Perdagangan Jalur Sutra Kuno (2 Tahun Lalu)',
        690,
        1650000,
        129000,
        '20:04',
      ),
      // 3 Tahun Lalu (790 - 1060 hari lalu)
      (
        'UC_demo_radit',
        'Raditya Dika',
        'Cerita Masa Kuliah di Luar Negeri (3 Tahun Lalu)',
        790,
        4200000,
        310000,
        '27:50',
      ),
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        'Mindset Keuangan di Usia 20-an (3 Tahun Lalu)',
        850,
        1780000,
        142000,
        '19:25',
      ),
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        'Bagaimana Cara Kerja Mesin Waktu Menurut Teori Relativitas?',
        910,
        1540000,
        126000,
        '14:30',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        'Top 1% Student Study Routine (3 Years Ago)',
        960,
        2450000,
        195000,
        '18:55',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        'Sejarah Nusantara Sebelum Era Kolonial (3 Tahun Lalu)',
        1020,
        2890000,
        224000,
        '25:40',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        'Diskusi Filsafat Klasik untuk Kehidupan Modern (3 Tahun Lalu)',
        1060,
        1190000,
        96000,
        '36:12',
      ),
      // 4 Tahun Lalu (1150 - 1430 hari lalu)
      (
        'UC_demo_radit',
        'Raditya Dika',
        'Bongkar Rahasia Menulis Buku & Skenario Film (4 Tahun Lalu)',
        1150,
        3850000,
        290000,
        '34:10',
      ),
      (
        'UC_demo_fajrul',
        'Fajrul Fx',
        'Video Sains Pertama: Kenapa Langit Berwarna Biru? (4 Tahun Lalu)',
        1220,
        890000,
        73000,
        '11:20',
      ),
      (
        'UC_demo_justin',
        'Justin Sung',
        'How I Transitioned from Medical School to Teaching (4 Years Ago)',
        1290,
        1620000,
        134000,
        '22:00',
      ),
      (
        'UC_demo_anim',
        'Animated History',
        'Asal Usul Peradaban Mesopotamia (4 Tahun Lalu)',
        1350,
        3120000,
        248000,
        '21:45',
      ),
      (
        'UC_demo_ferry',
        'Ferry Irwandi',
        'Belajar Videografi & Storytelling Sinematik (4 Tahun Lalu)',
        1400,
        1250000,
        99500,
        '16:50',
      ),
      (
        'UC_demo_malaka',
        'MALAKA',
        'Arsip Pemikiran: Membaca Ulang Sejarah Bangsa (4 Tahun Lalu)',
        1430,
        1410000,
        115000,
        '39:05',
      ),
    ];

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final ytId = ytThumbs[i % ytThumbs.length];
      _localVideos.add({
        'video_id': 'demo_${(i + 1).toString().padLeft(2, '0')}_$ytId',
        'channel_id': s.$1,
        'channel_title': s.$2,
        'channel_thumbnail': 'https://i.ytimg.com/vi/$ytId/default.jpg',
        'title': s.$3,
        'thumbnail_url': 'https://i.ytimg.com/vi/$ytId/hqdefault.jpg',
        'published_at': now.subtract(Duration(days: s.$4)).toIso8601String(),
        'view_count': s.$5,
        'like_count': s.$6,
        'duration': s.$7,
        'is_demo': 1,
      });
    }
  }

  Future<void> _loadBundledInitialDataIfNeeded() async {
    if (_bundledDataLoaded) return;
    _bundledDataLoaded = true;
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    try {
      final rawJson = await rootBundle.loadString('assets/initial_data.json');
      if (rawJson.isNotEmpty) {
        final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
        final bundledKey = (parsed['api_key'] ?? '').toString();
        final bundledCid = (parsed['my_channel_id'] ?? '').toString();
        final bundledChs = (parsed['channels'] as List?) ?? [];
        final bundledVids = (parsed['videos'] as List?) ?? [];
        if (bundledChs.isNotEmpty) {
          _localChannels
            ..clear()
            ..addAll(
              bundledChs.map((e) => Map<String, dynamic>.from(e as Map)),
            );
          _sortChannelsByWatchedDesc(_localChannels);
        }
        if (bundledVids.isNotEmpty) {
          _localVideos
            ..clear()
            ..addAll(
              bundledVids.map((e) => Map<String, dynamic>.from(e as Map)),
            );
        }
        if (bundledKey.isNotEmpty) {
          localApiKey = bundledKey;
          hasApiKey = true;
          apiKeyPreview = bundledKey.length > 8
              ? '${bundledKey.substring(0, 6)}...${bundledKey.substring(bundledKey.length - 4)}'
              : 'Terpasang';
        }
        if (bundledCid.isNotEmpty) {
          localMyChannelId = bundledCid;
        }
      }
      // The bundled file is only a seed. A standalone phone must restore its
      // own database after the seed has been loaded, otherwise every launch
      // discards videos fetched by Refresh.
      if (_isHpDevice) {
        final db = await _openStandaloneDatabase();
        final savedChannels = await db.query('channels', orderBy: 'rowid');
        final savedVideos = await db.query('videos', orderBy: 'rowid');
        if (savedChannels.isNotEmpty) {
          final chById = <String, Map<String, dynamic>>{
            for (final c in _localChannels)
              if ((c['channel_id'] ?? '').toString().isNotEmpty)
                (c['channel_id'] ?? '').toString(): c,
          };
          for (final row in savedChannels) {
            final parsedCh = Map<String, dynamic>.from(
              jsonDecode(row['data']! as String) as Map,
            );
            final cid = (parsedCh['channel_id'] ?? '').toString();
            if (cid.isNotEmpty) {
              chById[cid] = parsedCh;
            }
          }
          _localChannels
            ..clear()
            ..addAll(chById.values);
        }
        if (savedVideos.isNotEmpty) {
          final vidById = <String, Map<String, dynamic>>{
            for (final v in _localVideos)
              if ((v['video_id'] ?? '').toString().isNotEmpty)
                (v['video_id'] ?? '').toString(): v,
          };
          for (final row in savedVideos) {
            final parsedVid = Map<String, dynamic>.from(
              jsonDecode(row['data']! as String) as Map,
            );
            final vid = (parsedVid['video_id'] ?? '').toString();
            if (vid.isNotEmpty) {
              vidById[vid] = parsedVid;
            }
          }
          _localVideos
            ..clear()
            ..addAll(vidById.values);
        }
        _localUnsubscribedIds.clear();
        for (final c in _localChannels) {
          if ((c['status'] ?? 'subscribed') == 'unfollowed') {
            final cid = (c['channel_id'] ?? '').toString();
            if (cid.isNotEmpty) _localUnsubscribedIds.add(cid);
          }
        }
        _sortChannelsByWatchedDesc(_localChannels);
        final savedSettings = await db.query('settings');
        for (final row in savedSettings) {
          final k = (row['key'] ?? '').toString();
          final v = (row['value'] ?? '').toString();
          if (k == 'api_key' && v.isNotEmpty) {
            localApiKey = v;
            hasApiKey = true;
            apiKeyPreview = v.length > 8
                ? '${v.substring(0, 6)}...${v.substring(v.length - 4)}'
                : 'Terpasang';
          } else if (k == 'my_channel_id' && v.isNotEmpty) {
            localMyChannelId = v;
          }
        }
      }
    } catch (_) {}
  }

  Future<Database> _openStandaloneDatabase() => openDatabase(
    'standalone_cache.db',
    version: 2,
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE channels (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE videos (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
    },
  );

  Future<void> _saveStandaloneData() async {
    if (!_isHpDevice) return;
    try {
      final db = await _openStandaloneDatabase();
      await db.transaction((txn) async {
        await txn.delete('channels');
        await txn.delete('videos');
        final channelBatch = txn.batch();
        for (final channel in _localChannels) {
          final cid = (channel['channel_id'] ?? '').toString();
          if (cid.isEmpty) continue;
          channelBatch.insert('channels', {
            'id': cid,
            'data': jsonEncode(channel),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await channelBatch.commit(noResult: true);
        final videoBatch = txn.batch();
        for (final video in _localVideos) {
          final vid = (video['video_id'] ?? '').toString();
          if (vid.isEmpty) continue;
          videoBatch.insert('videos', {
            'id': vid,
            'data': jsonEncode(video),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await videoBatch.commit(noResult: true);
        if (localApiKey.isNotEmpty) {
          await txn.insert('settings', {
            'key': 'api_key',
            'value': localApiKey,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (localMyChannelId.isNotEmpty) {
          await txn.insert('settings', {
            'key': 'my_channel_id',
            'value': localMyChannelId,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } catch (_) {
      // Keep the current session usable if device storage is temporarily unavailable.
    }
  }

  static const List<String> _idShortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _formatDateId(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = _idShortMonths[dt.month - 1];
    return '$dd $mm ${dt.year}';
  }

  String _toDateIso(DateTime? dt) {
    if (dt == null) return '';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime? _parseDateIso(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final parts = text.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final today = _dateOnly(DateTime.now());
    final candidate = DateTime(y, m, d);
    if (candidate.isAfter(today)) return today;
    return candidate;
  }

  String _formatUtcIso(DateTime dt) {
    final u = dt.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    final hh = u.hour.toString().padLeft(2, '0');
    final mm = u.minute.toString().padLeft(2, '0');
    final ss = u.second.toString().padLeft(2, '0');
    return '$y-$m-${d}T$hh:$mm:${ss}Z';
  }

  bool _isNewerOrEqualIso(String incomingTs, String existingTs) {
    final inTrim = incomingTs.trim();
    final exTrim = existingTs.trim();
    if (inTrim.isEmpty) return false;
    if (exTrim.isEmpty) return true;
    final inDt = DateTime.tryParse(inTrim)?.toUtc();
    final exDt = DateTime.tryParse(exTrim)?.toUtc();
    if (inDt != null && exDt != null) {
      return !inDt.isBefore(exDt);
    }
    return inTrim.compareTo(exTrim) >= 0;
  }

  bool _isCustomDayPeriod(String p) =>
      p.endsWith('d') && int.tryParse(p.substring(0, p.length - 1)) != null;

  bool _isCustomYearPeriod(String p) =>
      p.endsWith('y') && int.tryParse(p.substring(0, p.length - 1)) != null;

  void _applyPeriodChoice(
    String nextPeriod, {
    DateTime? newCustomDate,
    DateTime? newRangeStart,
    DateTime? newRangeEnd,
  }) {
    final isDay = _isCustomDayPeriod(nextPeriod);
    if (!isDay) {
      _dayFocusNode.unfocus();
      _dayInputCtrl.clear();
    }
    setState(() {
      period = nextPeriod;
      currentPage = 1;
      customDate = nextPeriod == 'custom_date' ? newCustomDate : null;
      customRangeStart = nextPeriod == 'custom_range' ? newRangeStart : null;
      customRangeEnd = nextPeriod == 'custom_range' ? newRangeEnd : null;
    });
  }

  (String?, String?) _computePeriodUtcBounds() {
    final nowLocal = DateTime.now();
    final todayStart = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final nowUtc = nowLocal.toUtc();
    if (period == 'today') {
      final tomorrowStart = todayStart.add(const Duration(days: 1));
      return (_formatUtcIso(todayStart), _formatUtcIso(tomorrowStart));
    }
    if (period == 'week') {
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      return (_formatUtcIso(weekStart), null);
    }
    if (period == 'month') {
      final monthStart = DateTime(nowLocal.year, nowLocal.month, 1);
      return (_formatUtcIso(monthStart), null);
    }
    if (period == 'year') {
      final yearStart = DateTime(nowLocal.year, 1, 1);
      return (_formatUtcIso(yearStart), null);
    }
    if (period == 'custom_date' && customDate != null) {
      final d = _dateOnly(customDate!);
      final endExclusive = DateTime(
        d.year,
        d.month,
        d.day,
      ).add(const Duration(days: 1));
      return (null, _formatUtcIso(endExclusive));
    }
    if (period == 'custom_range' &&
        customRangeStart != null &&
        customRangeEnd != null) {
      final s = _dateOnly(customRangeStart!);
      final e = _dateOnly(customRangeEnd!);
      final startDt = s.isAfter(e) ? e : s;
      final endDt = s.isAfter(e) ? s : e;
      return (
        _formatUtcIso(startDt),
        _formatUtcIso(endDt.add(const Duration(days: 1))),
      );
    }
    if (_isCustomDayPeriod(period)) {
      final days = int.parse(period.substring(0, period.length - 1));
      if (days >= 1) {
        final startDt = todayStart.subtract(Duration(days: days));
        return (_formatUtcIso(startDt), null);
      }
    }
    if (_isCustomYearPeriod(period)) {
      final yrs = int.parse(period.substring(0, period.length - 1));
      if (yrs >= 1) {
        final startIso = _formatUtcIso(
          nowUtc.subtract(Duration(days: 365 * yrs)),
        );
        final endIso = yrs > 1
            ? _formatUtcIso(nowUtc.subtract(Duration(days: 365 * (yrs - 1))))
            : null;
        return (startIso, endIso);
      }
    }
    return (null, null);
  }

  String _periodDisplayLabel() {
    if (period == 'all') return 'All Time';
    if (period == 'today') return 'Today';
    if (period == 'week') return 'This Week';
    if (period == 'month') return 'This Month';
    if (period == 'year') return 'This Year';
    if (period == 'custom_date') {
      return customDate != null
          ? 'Custom Date (≤ ${_formatDateId(customDate!)})'
          : 'Custom Date';
    }
    if (period == 'custom_range') {
      if (customRangeStart != null && customRangeEnd != null) {
        return 'Range (${_formatDateId(customRangeStart!)} – ${_formatDateId(customRangeEnd!)})';
      }
      return 'Custom Date Range';
    }
    if (_isCustomDayPeriod(period)) {
      return '${period.substring(0, period.length - 1)} Day';
    }
    if (_isCustomYearPeriod(period)) {
      return '${period.substring(0, period.length - 1)} Tahun Lalu';
    }
    return 'All Time';
  }

  void _applyLocalFilterAndPagination() {
    final bounds = _computePeriodUtcBounds();
    final startDt = bounds.$1 != null
        ? DateTime.tryParse(bounds.$1!)?.toUtc()
        : null;
    final endDt = bounds.$2 != null
        ? DateTime.tryParse(bounds.$2!)?.toUtc()
        : null;

    int safeIntVal(dynamic raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse((raw ?? '0').toString()) ?? 0;
    }

    final unfollowedCids = <String>{
      ..._localUnsubscribedIds,
      for (final c in _localChannels)
        if ((c['status'] ?? 'subscribed') == 'unfollowed')
          (c['channel_id'] ?? '').toString(),
    };
    final hiddenCids = <String>{
      for (final c in _localChannels)
        if (_isHiddenFlag(c['is_hidden'])) (c['channel_id'] ?? '').toString(),
    };
    final visibleChannels = _localChannels
        .where(
          (c) => !unfollowedCids.contains((c['channel_id'] ?? '').toString()),
        )
        .toList();

    int cachedEpochMs(dynamic raw) {
      final s = (raw ?? '').toString().trim();
      if (s.isEmpty) return -1;
      return _pubEpochCache[s] ??=
          (DateTime.tryParse(s)?.toUtc().millisecondsSinceEpoch ?? -2);
    }

    final startMs = startDt?.millisecondsSinceEpoch;
    final endMs = endDt?.millisecondsSinceEpoch;

    final qLower = searchQuery.trim().toLowerCase();
    final minSec = durationRange.start.round() * 60;
    final maxSec = durationRange.end.round() * 60;
    final filtered = _localVideos.where((v) {
      final vCid = (v['channel_id'] ?? '').toString();
      if (unfollowedCids.contains(vCid)) {
        return false;
      }
      final vHidden =
          hiddenCids.contains(vCid) || _isHiddenFlag(v['channel_is_hidden']);
      if (!_matchesHideFilter(vHidden)) {
        return false;
      }
      if (selectedChannelId.isNotEmpty && vCid != selectedChannelId) {
        return false;
      }
      if (minSec > 0 || durationRange.end.round() < 120) {
        final rawDurSec = v['duration_seconds'];
        final durSec = rawDurSec != null
            ? safeIntVal(rawDurSec)
            : _durationToSeconds((v['duration'] ?? '').toString());
        if (minSec > 0 && durSec < minSec) return false;
        if (durationRange.end.round() < 120 && durSec > maxSec) return false;
      }
      if (qLower.isNotEmpty) {
        final t = (v['title'] ?? '').toString().toLowerCase();
        final ct = (v['channel_title'] ?? '').toString().toLowerCase();
        if (!t.contains(qLower) && !ct.contains(qLower)) return false;
      }
      if (startMs != null || endMs != null) {
        final pubMs = cachedEpochMs(v['published_at']);
        if (pubMs < 0) return false;
        if (startMs != null && pubMs < startMs) return false;
        if (endMs != null && pubMs >= endMs) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (sortBy == 'views') {
        final va = safeIntVal(a['view_count']) + safeIntVal(a['views_total']);
        final vb = safeIntVal(b['view_count']) + safeIntVal(b['views_total']);
        return vb.compareTo(va);
      } else if (sortBy == 'likes') {
        return safeIntVal(
          b['like_count'],
        ).compareTo(safeIntVal(a['like_count']));
      } else {
        final daMs = cachedEpochMs(a['published_at']);
        final dbMs = cachedEpochMs(b['published_at']);
        if (daMs == -1 && dbMs == -1) return 0;
        if (daMs == -1) return 1;
        if (dbMs == -1) return -1;
        if (daMs >= 0 && dbMs >= 0) {
          return sortBy == 'oldest'
              ? daMs.compareTo(dbMs)
              : dbMs.compareTo(daMs);
        }
        final pa = (a['published_at'] ?? '').toString().trim();
        final pb = (b['published_at'] ?? '').toString().trim();
        return sortBy == 'oldest' ? pa.compareTo(pb) : pb.compareTo(pa);
      }
    });

    final total = filtered.length;
    final pages = total == 0 ? 1 : ((total + limit - 1) ~/ limit);
    final safePage = currentPage.clamp(1, pages);
    final startIdx = (safePage - 1) * limit;
    final endIdx = (startIdx + limit > total) ? total : startIdx + limit;

    final localLive = <Map<String, dynamic>>[];
    final liveBestByCid = <String, Map<String, dynamic>>{};
    for (final v in _localVideos) {
      final isLive = _isLiveFlag(v['is_live']);
      if (!isLive) continue;
      final vCid = (v['channel_id'] ?? '').toString();
      if (vCid.isEmpty || unfollowedCids.contains(vCid)) continue;
      Map<String, dynamic>? chMeta;
      for (final c in _localChannels) {
        if ((c['channel_id'] ?? '').toString() == vCid) {
          chMeta = c;
          break;
        }
      }
      final wc = int.tryParse(
            (chMeta?['views_total'] ?? chMeta?['watched_count'] ?? 0)
                .toString(),
          ) ??
          0;
      final candidate = {
        ...v,
        'channel_title':
            (chMeta?['title'] ?? v['channel_title'] ?? '').toString(),
        'channel_thumbnail':
            (chMeta?['thumbnail_url'] ?? v['channel_thumbnail'] ?? '')
                .toString(),
        'channel_is_hidden':
            chMeta?['is_hidden'] ?? v['channel_is_hidden'] ?? 0,
        'watched_count': wc,
      };
      final prev = liveBestByCid[vCid];
      if (prev == null ||
          (candidate['published_at'] ?? '').toString().compareTo(
                (prev['published_at'] ?? '').toString(),
              ) >
              0) {
        liveBestByCid[vCid] = candidate;
      }
    }
    localLive.addAll(liveBestByCid.values);
    localLive.sort((a, b) {
      final wa = int.tryParse((a['watched_count'] ?? 0).toString()) ?? 0;
      final wb = int.tryParse((b['watched_count'] ?? 0).toString()) ?? 0;
      if (wb != wa) return wb.compareTo(wa);
      return (b['published_at'] ?? '').toString().compareTo(
            (a['published_at'] ?? '').toString(),
          );
    });

    setState(() {
      isStandaloneMode = true;
      channels = visibleChannels;
      liveStreams = localLive;
      totalVideos = total;
      totalPages = pages;
      currentPage = safePage;
      videos = startIdx < total ? filtered.sublist(startIdx, endIdx) : [];
      loading = false;
    });
    _refreshFilterModal?.call();
  }

  Future<void> _restoreSessionAndFetch() async {
    setState(() => loading = true);
    await _loadBundledInitialDataIfNeeded();
    try {
      http.Response? stateRes;
      final candidates = <String>{
        baseUrl,
        'http://127.0.0.1:8000',
        'http://172.18.164.232:8000',
        'http://192.168.68.54:8000',
      };
      for (final candidate in candidates) {
        try {
          final r = await http
              .get(Uri.parse('$candidate/api/state'))
              .timeout(const Duration(milliseconds: 1200));
          if (r.statusCode == 200) {
            baseUrl = candidate;
            stateRes = r;
            break;
          }
        } catch (_) {}
      }
      if (stateRes != null && stateRes.statusCode == 200) {
        final sData = jsonDecode(stateRes.body);
        final sess = (sData['session_state'] as Map?) ?? {};
        final rState = (sData['refresh_state'] as Map?) ?? {};
        final rRunning = (rState['running'] as bool?) ?? false;
        final rReady = (rState['done_ready'] as bool?) ?? false;
        final rProg = (rState['progress'] as int?) ?? 0;
        final rNewVids = (rState['new_videos'] as int?) ?? 0;

        if (!mounted) return;
        final sessChannel = (sess['channel_id'] ?? '').toString();
        setState(() {
          isStandaloneMode = false;
          channels = List<Map<String, dynamic>>.from(sData['channels'] ?? []);
          liveStreams = List<Map<String, dynamic>>.from(
            sData['live_streams'] ?? [],
          );
          _sortChannelsByWatchedDesc(channels);
          hasApiKey = sData['has_api_key'] ?? false;
          apiKeyPreview = sData['api_key_preview'] ?? '';
          defaultLimit = 50;
          tabLimits = {};
          sortBy = (sess['sort_by'] ?? 'time').toString();
          period = (sess['period'] ?? 'all').toString();
          customDate = period == 'custom_date'
              ? _parseDateIso(sess['custom_date'])
              : null;
          customRangeStart = period == 'custom_range'
              ? _parseDateIso(sess['range_start'])
              : null;
          customRangeEnd = period == 'custom_range'
              ? _parseDateIso(sess['range_end'])
              : null;
          hideFilter = 'unhide';
          if (_isCustomDayPeriod(period)) {
            _dayInputCtrl.text = period.substring(0, period.length - 1);
          } else {
            _dayInputCtrl.clear();
          }
          selectedChannelId = sessChannel;
          searchQuery = (sess['q'] ?? '').toString();
          _searchCtrl.text = searchQuery;
          currentPage = (sess['page'] as int?) ?? 1;
          durationRange = const RangeValues(0, 120);
          final rawSidebarMode = (sess['sidebar_mode'] ?? 'full').toString();
          sidebarMode = rawSidebarMode == 'hidden' ? 'hidden' : 'full';
          filterMinimized = (sess['filter_minimized'] as bool?) ?? false;
          limit = 50;
          refreshingYouTube = rRunning;
          refreshReadyGreen = rReady;
          refreshProgress = rProg;
          refreshNewVideosCount = rNewVids;
        });
        if (rRunning) {
          _startRefreshPolling();
        }
      }
    } catch (_) {}
    await _fetchVideos();
    _triggerAutoRefreshYouTube();
  }

  bool _isLiveFlag(dynamic val) =>
      val == 1 || val == true || val?.toString() == '1';

  List<Map<String, dynamic>> _visibleLiveStreams({
    bool ignoreSelectedChannel = false,
  }) {
    final hiddenMap = <String, bool>{};
    final unfollowedSet = <String>{..._localUnsubscribedIds};
    for (final c in channels) {
      final cid = (c['channel_id'] ?? '').toString();
      hiddenMap[cid] = _isHiddenFlag(c['is_hidden']);
      if ((c['status'] ?? 'subscribed') == 'unfollowed') {
        unfollowedSet.add(cid);
      }
    }
    final result = <Map<String, dynamic>>[];
    final seenCids = <String>{};
    for (final item in liveStreams) {
      final cid = (item['channel_id'] ?? '').toString();
      if (cid.isEmpty || unfollowedSet.contains(cid)) continue;
      final isHidden = hiddenMap.containsKey(cid)
          ? hiddenMap[cid]!
          : _isHiddenFlag(item['channel_is_hidden']);
      if (!_matchesHideFilter(isHidden)) continue;
      if (!ignoreSelectedChannel &&
          selectedChannelId.isNotEmpty &&
          cid != selectedChannelId) {
        continue;
      }
      if (seenCids.contains(cid)) continue;
      seenCids.add(cid);
      result.add(item);
    }
    return result;
  }

  void _triggerAutoRefreshYouTube() {
    if (_didInitialAutoRefresh ||
        !mounted ||
        refreshingYouTube ||
        refreshReadyGreen) {
      return;
    }
    final hasCreds = isStandaloneMode
        ? localApiKey.trim().isNotEmpty
        : hasApiKey;
    if (!hasCreds) return;
    _didInitialAutoRefresh = true;
    _manualRefreshYouTube(isAuto: true);
  }

  void _startRefreshPolling() {
    _refreshPollTimer?.cancel();
    _refreshPollTimer = Timer.periodic(const Duration(milliseconds: 600), (
      timer,
    ) async {
      if (!mounted || isStandaloneMode) {
        timer.cancel();
        return;
      }
      try {
        final res = await http
            .get(Uri.parse('$baseUrl/api/refresh-youtube/status'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final running = (data['running'] as bool?) ?? false;
          final prog = (data['progress'] as int?) ?? 0;
          final ready = (data['done_ready'] as bool?) ?? false;
          final newVids = (data['new_videos'] as int?) ?? 0;
          final err = (data['error'] ?? '').toString();

          if (!mounted) return;
          setState(() {
            refreshingYouTube = running;
            refreshProgress = prog;
            refreshReadyGreen = ready;
            refreshNewVideosCount = newVids;
          });

          if (!running) {
            timer.cancel();
            if (err.isNotEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.redAccent,
                  content: Text('⚠️ Gagal Refresh YouTube: $err'),
                ),
              );
            } else if (ready) {
              try {
                await http.post(
                  Uri.parse('$baseUrl/api/refresh-youtube/consume'),
                );
              } catch (_) {}
              if (!mounted) return;
              setState(() {
                refreshingYouTube = false;
                refreshReadyGreen = false;
                refreshProgress = 0;
                refreshNewVideosCount = newVids;
                currentPage = 1;
              });
              await _fetchVideos();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1B5E20),
                  content: Text(
                    '✅ Sync selesai! ($newVids video baru dimuat, Total: $totalVideos video)',
                  ),
                ),
              );
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _saveUiPreferences({
    int? newLimit,
    String? newSidebarMode,
    bool? newFilterMinimized,
  }) async {
    final tabKey = selectedChannelId.isEmpty ? 'home' : selectedChannelId;
    if (newLimit != null &&
        (newLimit == 25 || newLimit == 50 || newLimit == 100)) {
      defaultLimit = newLimit;
      tabLimits[tabKey] = newLimit;
    }
    if (!isStandaloneMode) {
      final bounds = _computePeriodUtcBounds();
      try {
        await http.post(
          Uri.parse('$baseUrl/api/ui-state'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sort_by': sortBy,
            'period': period,
            'custom_date': _toDateIso(customDate),
            'range_start': _toDateIso(customRangeStart),
            'range_end': _toDateIso(customRangeEnd),
            'start_at': bounds.$1 ?? '',
            'end_at': bounds.$2 ?? '',
            'hide_filter': hideFilter,
            'channel_id': selectedChannelId,
            'q': searchQuery,
            'page': currentPage,
            'min_minutes': durationRange.start.round(),
            'max_minutes': durationRange.end.round(),
            'limit': newLimit,
            'sidebar_mode': newSidebarMode ?? sidebarMode,
            'filter_minimized': newFilterMinimized ?? filterMinimized,
          }),
        );
      } catch (_) {}
    }
  }

  Future<void> _manualRefreshYouTube({bool isAuto = false}) async {
    // 1. Jika tombol sudah HIJAU (Sync 100% selesai), klik tombol hijau langsung menampilkan video baru ke layar!
    if (refreshReadyGreen) {
      if (!isStandaloneMode) {
        try {
          await http.post(Uri.parse('$baseUrl/api/refresh-youtube/consume'));
        } catch (_) {}
      }
      final addedCount = refreshNewVideosCount;
      if (!mounted) return;
      setState(() {
        refreshReadyGreen = false;
        refreshProgress = 0;
        currentPage = 1;
      });
      await _fetchVideos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B5E20),
            content: Text(
              '✅ Video terbaru berhasil ditampilkan! ($addedCount video baru dimuat, Total: $totalVideos video)',
            ),
          ),
        );
      }
      return;
    }

    // 2. Jika sedang proses sync di background (0%..99%), biarkan user tetap menjelajah tanpa memblokir layar
    if (refreshingYouTube) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF303030),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            content: Text(
              '⏳ Sinkronisasi berjalan di latar belakang ($refreshProgress%)... Video baru akan otomatis muncul saat 100%.',
            ),
          ),
        );
      }
      return;
    }

    // Jika backend laptop tidak terjangkau (mis. HP tanpa USB/backend mati), otomatis pakai Mode Mandiri
    if (!isStandaloneMode) {
      try {
        await http
            .get(Uri.parse('$baseUrl/api/state'))
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {
        isStandaloneMode = true;
      }
    }

    // 3. Tombol MERAH ditekan -> Mulai sinkronisasi di latar belakang (0% -> 100%) tanpa harus ditunggu
    if (!mounted) return;
    setState(() {
      refreshingYouTube = true;
      refreshProgress = 2;
      refreshReadyGreen = false;
    });

    try {
      if (isStandaloneMode) {
        if (localApiKey.isEmpty) {
          throw Exception('Masukkan API Key terlebih dahulu di menu ⚙️.');
        }
        final beforeCount = _localVideos.length;
        // 1. Cek daftar Subscriptions terbaru via Channel ID user + API Key
        if (localMyChannelId.isNotEmpty && selectedChannelId.isEmpty) {
          await _standaloneSyncSubscriptionsByMyChannel();
        }
        final targetChs = _localChannels.where((ch) {
          final cid = (ch['channel_id'] ?? '').toString();
          if (cid.startsWith('UC_demo_')) return false;
          if ((ch['status'] ?? 'subscribed') == 'unfollowed' ||
              _localUnsubscribedIds.contains(cid)) {
            return false;
          }
          return selectedChannelId.isEmpty || cid == selectedChannelId;
        }).toList();
        await _standaloneFastRefreshChannels(targetChs);
        await _saveStandaloneData();
        final newVids = (_localVideos.length - beforeCount).clamp(0, 999999);
        if (!mounted) return;
        setState(() {
          refreshingYouTube = false;
          refreshProgress = 0;
          refreshReadyGreen = false;
          refreshNewVideosCount = newVids;
          currentPage = 1;
        });
        await _fetchVideos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1B5E20),
              content: Text(
                '✅ Sync selesai! ($newVids video baru dimuat, Total: $totalVideos video)',
              ),
            ),
          );
        }
      } else {
        final res = await http.post(
          Uri.parse('$baseUrl/api/refresh-youtube'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'channel_id': selectedChannelId}),
        );
        if (res.statusCode == 200) {
          _startRefreshPolling();
        } else {
          final err = jsonDecode(res.body);
          throw Exception(err['detail'] ?? 'Gagal memulai Refresh YouTube');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          refreshingYouTube = false;
          refreshProgress = 0;
        });
        if (!isAuto) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                '⚠️ Gagal Refresh YouTube: ${e.toString().replaceAll("Exception: ", "")}',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _refreshAll() async {
    await _fetchVideos();
  }

  Future<void> _fetchVideos({bool silent = false}) async {
    final seq = ++_fetchVideosSeq;
    if (isStandaloneMode) {
      _applyLocalFilterAndPagination();
      return;
    }
    if (!silent) setState(() => loading = true);
    try {
      final stateRes = await http
          .get(Uri.parse('$baseUrl/api/state'))
          .timeout(const Duration(seconds: 4));
      if (!mounted || seq != _fetchVideosSeq) return;
      final bounds = _computePeriodUtcBounds();
      final uri = Uri.parse('$baseUrl/api/videos').replace(
        queryParameters: {
          'sort_by': sortBy,
          'period': period,
          'custom_date': _toDateIso(customDate),
          'range_start': _toDateIso(customRangeStart),
          'range_end': _toDateIso(customRangeEnd),
          'start_at': bounds.$1 ?? '',
          'end_at': bounds.$2 ?? '',
          'hide_filter': hideFilter,
          'channel_id': selectedChannelId,
          'q': searchQuery,
          'limit': limit.toString(),
          'page': currentPage.toString(),
          'min_minutes': durationRange.start.round().toString(),
          'max_minutes': durationRange.end.round().toString(),
        },
      );
      final vidRes = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted || seq != _fetchVideosSeq) return;
      if (stateRes.statusCode == 200 && vidRes.statusCode == 200) {
        final sData = jsonDecode(stateRes.body);
        final vData = jsonDecode(vidRes.body);
        if (!mounted || seq != _fetchVideosSeq) return;
        final fetchedChannels = List<Map<String, dynamic>>.from(
          sData['channels'] ?? [],
        );
        final fetchedVideos = List<Map<String, dynamic>>.from(
          vData['items'] ?? [],
        );
        for (final fetched in fetchedChannels) {
          for (final saved in _localChannels) {
            if ((saved['channel_id'] ?? '').toString() ==
                (fetched['channel_id'] ?? '').toString()) {
              _mergeUsageCounts(fetched, saved, isChannel: true);
              break;
            }
          }
        }
        for (final fetched in fetchedVideos) {
          for (final saved in _localVideos) {
            if ((saved['video_id'] ?? '').toString() ==
                (fetched['video_id'] ?? '').toString()) {
              _mergeUsageCounts(fetched, saved);
              break;
            }
          }
        }
        if (!mounted) return;
        final nextTotalVideos =
            int.tryParse((vData['total'] ?? 0).toString()) ?? 0;
        final nextTotalPages =
            (int.tryParse((vData['total_pages'] ?? 1).toString()) ?? 1).clamp(
              1,
              999999,
            );
        if (fetchedVideos.isEmpty &&
            nextTotalVideos > 0 &&
            currentPage > nextTotalPages) {
          currentPage = nextTotalPages;
          final clampedUri = uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'page': currentPage.toString(),
            },
          );
          final retryRes = await http
              .get(clampedUri)
              .timeout(const Duration(seconds: 15));
          if (!mounted || seq != _fetchVideosSeq) return;
          if (retryRes.statusCode == 200) {
            final retryData = jsonDecode(retryRes.body);
            final retryVideos = List<Map<String, dynamic>>.from(
              retryData['items'] ?? [],
            );
            for (final fetched in retryVideos) {
              for (final saved in _localVideos) {
                if ((saved['video_id'] ?? '').toString() ==
                    (fetched['video_id'] ?? '').toString()) {
                  _mergeUsageCounts(fetched, saved);
                  break;
                }
              }
            }
            setState(() {
              isStandaloneMode = false;
              channels = fetchedChannels;
              liveStreams = List<Map<String, dynamic>>.from(
                retryData['live_streams'] ?? sData['live_streams'] ?? [],
              );
              _sortChannelsByWatchedDesc(channels);
              hasApiKey = sData['has_api_key'] ?? false;
              apiKeyPreview = sData['api_key_preview'] ?? '';
              videos = retryVideos;
              totalVideos = nextTotalVideos;
              totalPages = nextTotalPages;
              loading = false;
            });
            _refreshFilterModal?.call();
            return;
          }
        }
        setState(() {
          isStandaloneMode = false;
          channels = fetchedChannels;
          liveStreams = List<Map<String, dynamic>>.from(
            vData['live_streams'] ?? sData['live_streams'] ?? [],
          );
          _sortChannelsByWatchedDesc(channels);
          hasApiKey = sData['has_api_key'] ?? false;
          apiKeyPreview = sData['api_key_preview'] ?? '';
          videos = fetchedVideos;
          totalVideos = nextTotalVideos;
          totalPages = nextTotalPages;
          currentPage = currentPage.clamp(1, nextTotalPages);
          loading = false;
        });
        _refreshFilterModal?.call();
        return;
      }
    } catch (_) {
      // Jika tidak ada backend Python (misal saat jalan mandiri sebagai APK di HP),
      // otomatis gunakan Mesin Mandiri (Standalone Mode) tanpa error!
    }
    if (!mounted || seq != _fetchVideosSeq) return;
    _applyLocalFilterAndPagination();
  }

  Future<void> _standaloneSyncSubscriptionsByMyChannel() async {
    if (localMyChannelId.isEmpty || localApiKey.isEmpty) return;
    final client = http.Client();
    try {
      final existingCids = _localChannels
          .map((c) => (c['channel_id'] ?? '').toString())
          .toSet();
      String? pageToken;
      for (var page = 0; page < 50; page++) {
        final params = <String, String>{
          'part': 'snippet',
          'channelId': localMyChannelId,
          'maxResults': '50',
          'order': 'alphabetical',
          'key': localApiKey,
        };
        if (pageToken != null && pageToken.isNotEmpty) {
          params['pageToken'] = pageToken;
        }
        final uri = Uri.https(
          'www.googleapis.com',
          '/youtube/v3/subscriptions',
          params,
        );
        final res = await client.get(uri).timeout(const Duration(seconds: 5));
        final data = jsonDecode(res.body);
        if (res.statusCode != 200 || data['error'] != null) {
          final msg =
              (data['error']?['message'] ??
                      'Gagal mengambil daftar subscriptions (${res.statusCode})')
                  .toString();
          throw Exception(msg);
        }
        final items = (data['items'] as List?) ?? [];
        for (final item in items) {
          final snip = item['snippet'] ?? {};
          final cid = (snip['resourceId']?['channelId'] ?? '').toString();
          if (cid.isEmpty ||
              existingCids.contains(cid) ||
              _localUnsubscribedIds.contains(cid)) {
            continue;
          }
          final title = (snip['title'] ?? cid).toString();
          final thumb = (snip['thumbnails']?['default']?['url'] ?? '')
              .toString();
          _localChannels.add({
            'channel_id': cid,
            'title': title,
            'handle': '',
            'thumbnail_url': thumb,
            'uploads_playlist_id': cid.startsWith('UC')
                ? 'UU${cid.substring(2)}'
                : cid,
            'source': 'subscriptions',
            'video_count': 0,
            'watched_count': 0,
          });
          existingCids.add(cid);
        }
        pageToken = data['nextPageToken']?.toString();
        if (pageToken == null || pageToken.isEmpty) break;
      }
      _sortChannelsByWatchedDesc(_localChannels);
    } catch (_) {
    } finally {
      client.close();
    }
  }

  Future<void> _standaloneFastRefreshChannels(
    List<Map<String, dynamic>> targetChs,
  ) async {
    if (targetChs.isEmpty) return;
    final targetCids = targetChs
        .map((c) => (c['channel_id'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toSet();
    final recentCutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 48))
        .toIso8601String();
    final liveRssCutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 14))
        .toIso8601String();

    final knownOldVidIds = <String>{};
    final zeroDurVidIds = <String>{};
    final existingVidIds = <String>{};
    final existingLiveIds = <String>{};
    final chMetaMap = <String, Map<String, String>>{};
    for (final ch in targetChs) {
      final cid = (ch['channel_id'] ?? '').toString();
      chMetaMap[cid] = {
        'channel_id': cid,
        'channel_title': (ch['title'] ?? '').toString(),
        'channel_thumbnail': (ch['thumbnail_url'] ?? '').toString(),
      };
    }
    final newVidMeta = <String, Map<String, String>>{};
    for (final v in _localVideos) {
      final vCid = (v['channel_id'] ?? '').toString();
      final vid = (v['video_id'] ?? '').toString();
      if (vid.isEmpty) continue;
      existingVidIds.add(vid);
      final pubAt = (v['published_at'] ?? '').toString().trim();
      final durSec =
          int.tryParse((v['duration_seconds'] ?? 0).toString()) ?? 0;
      final isLive = _isLiveFlag(v['is_live']);
      if (durSec <= 0) {
        zeroDurVidIds.add(vid);
      }
      if (pubAt.isNotEmpty &&
          pubAt.compareTo(recentCutoff) < 0 &&
          durSec > 0 &&
          !isLive) {
        knownOldVidIds.add(vid);
      }
      if (isLive && targetCids.contains(vCid)) {
        existingLiveIds.add(vid);
        newVidMeta[vid] = chMetaMap[vCid] ?? {'channel_id': vCid};
      }
    }

    final entryBlockRegex = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    final vidRegex = RegExp(r'<yt:videoId>([^<]+)</yt:videoId>');
    final updRegex = RegExp(r'<updated>([^<]+)</updated>');
    final pubRegex = RegExp(r'<published>([^<]+)</published>');

    final client = http.Client();
    try {
      var nextIdx = 0;
      var doneCount = 0;
      final concurrency = targetChs.length < 18 ? targetChs.length : 18;

      Future<String?> fetchRss(Uri uri) async {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final res = await client
                .get(uri)
                .timeout(const Duration(seconds: 6));
            if (res.statusCode == 200) return res.body;
            if ((res.statusCode == 429 || res.statusCode >= 500) &&
                attempt < 2) {
              await Future.delayed(
                Duration(milliseconds: 250 * (attempt + 1)),
              );
              continue;
            }
            return null;
          } catch (_) {
            if (attempt < 2) {
              await Future.delayed(
                Duration(milliseconds: 250 * (attempt + 1)),
              );
            }
          }
        }
        return null;
      }

      Future<void> worker() async {
        while (true) {
          if (nextIdx >= targetChs.length) return;
          final ch = targetChs[nextIdx++];
          final cid = (ch['channel_id'] ?? '').toString();
          if (cid.startsWith('UC')) {
            final meta = {
              'channel_id': cid,
              'channel_title': (ch['title'] ?? '').toString(),
              'channel_thumbnail': (ch['thumbnail_url'] ?? '').toString(),
            };
            final mainXml = await fetchRss(
              Uri.parse(
                'https://www.youtube.com/feeds/videos.xml?channel_id=$cid',
              ),
            );
            if (mainXml != null) {
              for (final m in vidRegex.allMatches(mainXml)) {
                final vid = (m.group(1) ?? '').trim();
                if (vid.isNotEmpty && !knownOldVidIds.contains(vid)) {
                  newVidMeta[vid] = meta;
                }
              }
            }
            if (cid.length > 2) {
              final uulv = 'UULV${cid.substring(2)}';
              final liveXml = await fetchRss(
                Uri.parse(
                  'https://www.youtube.com/feeds/videos.xml?playlist_id=$uulv',
                ),
              );
              if (liveXml != null) {
                for (final blockMatch in entryBlockRegex.allMatches(liveXml)) {
                  final block = blockMatch.group(1) ?? '';
                  final vid = (vidRegex.firstMatch(block)?.group(1) ?? '')
                      .trim();
                  if (vid.isEmpty) continue;
                  final upd =
                      (updRegex.firstMatch(block)?.group(1) ??
                              pubRegex.firstMatch(block)?.group(1) ??
                              '')
                          .trim();
                  final recentEnough =
                      upd.isNotEmpty && upd.compareTo(liveRssCutoff) >= 0;
                  if (recentEnough ||
                      !knownOldVidIds.contains(vid) ||
                      zeroDurVidIds.contains(vid) ||
                      existingLiveIds.contains(vid)) {
                    newVidMeta[vid] = meta;
                  }
                }
              }
            }
          }
          doneCount++;
          if (mounted &&
              (doneCount % 15 == 0 || doneCount == targetChs.length)) {
            setState(() {
              refreshProgress = (doneCount * 90 ~/ targetChs.length).clamp(
                5,
                92,
              );
            });
          }
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));

      final stillLiveIds = <String>{};
      final checkedIds = <String>{};
      final newIds = newVidMeta.keys.toList();
      final detailSlices = <List<String>>[];
      for (var i = 0; i < newIds.length; i += 50) {
        detailSlices.add(
          newIds.sublist(i, (i + 50 > newIds.length) ? newIds.length : i + 50),
        );
      }
      var nextSliceIdx = 0;
      Future<void> detailWorker() async {
        while (true) {
          if (nextSliceIdx >= detailSlices.length) return;
          final slice = detailSlices[nextSliceIdx++];
          final vUri = Uri.https('www.googleapis.com', '/youtube/v3/videos', {
            'part': 'snippet,statistics,contentDetails',
            'id': slice.join(','),
            'key': localApiKey,
          });
          http.Response? vRes;
          for (var attempt = 0; attempt < 2; attempt++) {
            try {
              vRes = await client.get(vUri).timeout(const Duration(seconds: 15));
              if (vRes.statusCode == 200 || attempt == 1) break;
            } catch (e) {
              if (attempt == 1) rethrow;
            }
            await Future.delayed(const Duration(milliseconds: 250));
          }
          if (vRes == null) continue;
          final vData = jsonDecode(vRes.body);
          if (vRes.statusCode != 200 || vData['error'] != null) {
            final msg =
                (vData['error']?['message'] ??
                        'YouTube API error (${vRes.statusCode})')
                    .toString();
            throw Exception(msg);
          }
          checkedIds.addAll(slice);
          final vItems = (vData['items'] as List?) ?? [];
          for (final v in vItems) {
            final vid = (v['id'] ?? '').toString();
            if (vid.isEmpty) continue;
            final vsnip = v['snippet'] ?? {};
            final vstats = v['statistics'] ?? {};
            final meta = newVidMeta[vid] ?? {};
            final cid = (vsnip['channelId'] ?? meta['channel_id'] ?? '')
                .toString();
            final durStr = _parseIsoDuration(
              (v['contentDetails']?['duration'] ?? '').toString(),
            );
            final isLiveVal =
                (vsnip['liveBroadcastContent'] ?? '').toString() == 'live'
                    ? 1
                    : 0;
            if (isLiveVal == 1) {
              stillLiveIds.add(vid);
            }
            final thumbUrl =
                (vsnip['thumbnails']?['high']?['url'] ??
                        vsnip['thumbnails']?['medium']?['url'] ??
                        'https://i.ytimg.com/vi/$vid/hqdefault.jpg')
                    .toString();
            final existingIdx = _localVideos.indexWhere(
              (old) => old['video_id'] == vid,
            );
            if (existingIdx >= 0) {
              _localVideos[existingIdx]['title'] =
                  (vsnip['title'] ?? _localVideos[existingIdx]['title'] ?? '')
                      .toString();
              _localVideos[existingIdx]['thumbnail_url'] = thumbUrl;
              if (vsnip['publishedAt'] != null) {
                _localVideos[existingIdx]['published_at'] =
                    vsnip['publishedAt'].toString();
              }
              _localVideos[existingIdx]['view_count'] =
                  int.tryParse((vstats['viewCount'] ?? '0').toString()) ?? 0;
              _localVideos[existingIdx]['like_count'] =
                  int.tryParse((vstats['likeCount'] ?? '0').toString()) ?? 0;
              _localVideos[existingIdx]['duration'] = durStr;
              _localVideos[existingIdx]['duration_seconds'] =
                  _durationToSeconds(durStr);
              _localVideos[existingIdx]['is_live'] = isLiveVal;
              continue;
            }
            if (existingVidIds.contains(vid)) continue;
            existingVidIds.add(vid);
            _localVideos.insert(0, {
              'video_id': vid,
              'channel_id': cid,
              'channel_title':
                  (vsnip['channelTitle'] ?? meta['channel_title'] ?? '')
                      .toString(),
              'channel_thumbnail': (meta['channel_thumbnail'] ?? '').toString(),
              'title': (vsnip['title'] ?? 'Untitled').toString(),
              'thumbnail_url': thumbUrl,
              'published_at':
                  (vsnip['publishedAt'] ??
                          DateTime.now().toUtc().toIso8601String())
                      .toString(),
              'view_count':
                  int.tryParse((vstats['viewCount'] ?? '0').toString()) ?? 0,
              'like_count':
                  int.tryParse((vstats['likeCount'] ?? '0').toString()) ?? 0,
              'duration': durStr,
              'duration_seconds': _durationToSeconds(durStr),
              'watched_count': _getCreatorWatchedCount(cid),
              'is_demo': 0,
              'is_live': isLiveVal,
            });
          }
        }
      }

      if (detailSlices.isNotEmpty) {
        final detailConcurrency = detailSlices.length < 4
            ? detailSlices.length
            : 4;
        await Future.wait(
          List.generate(detailConcurrency, (_) => detailWorker()),
        );
      }
      if (existingLiveIds.isNotEmpty) {
        for (final v in _localVideos) {
          final vid = (v['video_id'] ?? '').toString();
          if (existingLiveIds.contains(vid) &&
              checkedIds.contains(vid) &&
              !stillLiveIds.contains(vid)) {
            v['is_live'] = 0;
          }
        }
      }
    } finally {
      client.close();
    }
  }

  // Fungsi Mandiri (Standalone di HP) untuk langsung memanggil API YouTube tanpa Backend Python
  Future<void> _standaloneAddAndSyncChannel(String identifier) async {
    String raw = identifier.trim();
    if (raw.isEmpty) throw Exception('Masukkan @handle atau ID Channel');
    if (localApiKey.isEmpty) {
      throw Exception(
        'Masukkan YouTube API Key dulu di menu Pengaturan API (⚙️).',
      );
    }
    if (raw.contains('youtube.com/')) {
      if (raw.contains('/@')) {
        raw = '@${raw.split('/@')[1].split('/')[0].split('?')[0]}';
      } else if (raw.contains('/channel/')) {
        raw = raw.split('/channel/')[1].split('/')[0].split('?')[0];
      }
    }

    final queryParams = <String, String>{
      'part': 'snippet,contentDetails',
      'key': localApiKey,
    };
    if (raw.startsWith('@')) {
      queryParams['forHandle'] = raw;
    } else if (raw.startsWith('UC') && raw.length >= 20) {
      queryParams['id'] = raw;
    } else {
      queryParams['forHandle'] = '@$raw';
    }

    final chUri = Uri.https(
      'www.googleapis.com',
      '/youtube/v3/channels',
      queryParams,
    );
    final chRes = await http.get(chUri).timeout(const Duration(seconds: 12));
    if (chRes.statusCode != 200) {
      throw Exception('Gagal mengambil info channel (${chRes.statusCode}).');
    }
    final chData = jsonDecode(chRes.body);
    final items = (chData['items'] as List?) ?? [];
    if (items.isEmpty) {
      throw Exception(
        'Channel "$identifier" tidak ditemukan atau API Key kurang tepat.',
      );
    }

    final ch = items[0];
    final cid = ch['id'].toString();
    final snip = ch['snippet'] ?? {};
    final title = (snip['title'] ?? raw).toString();
    final handle = (snip['customUrl'] ?? raw).toString();
    final thumbUrl =
        ((snip['thumbnails']?['medium'] ??
                    snip['thumbnails']?['default'])?['url'] ??
                '')
            .toString();
    final uploadsPid =
        (ch['contentDetails']?['relatedPlaylists']?['uploads'] ??
                (cid.startsWith('UC') ? 'UU${cid.substring(2)}' : cid))
            .toString();

    _localUnsubscribedIds.remove(cid);
    Map<String, dynamic>? prevCh;
    for (final c in _localChannels) {
      if ((c['channel_id'] ?? '').toString() == cid) {
        prevCh = c;
        break;
      }
    }
    _localChannels.removeWhere((c) => c['channel_id'] == cid);
    _localChannels.add({
      'channel_id': cid,
      'title': title,
      'handle': handle,
      'thumbnail_url': thumbUrl,
      'uploads_playlist_id': uploadsPid,
      'source': 'manual',
      'video_count': prevCh?['video_count'] ?? 0,
      'watched_count': prevCh?['watched_count'] ?? 0,
      'views_hp': prevCh?['views_hp'] ?? 0,
      'views_laptop': prevCh?['views_laptop'] ?? 0,
      'views_total': prevCh?['views_total'] ?? 0,
      'status': 'subscribed',
    });

    // Ambil 50 video terbaru dari playlist uploads (hemat kuota: 1 poin)
    final plUri = Uri.https('www.googleapis.com', '/youtube/v3/playlistItems', {
      'part': 'contentDetails',
      'playlistId': uploadsPid,
      'maxResults': '50',
      'key': localApiKey,
    });
    final plRes = await http.get(plUri).timeout(const Duration(seconds: 12));
    if (plRes.statusCode != 200) {
      await _saveStandaloneData();
      return;
    }
    final plItems = (jsonDecode(plRes.body)['items'] as List?) ?? [];
    final videoIds = plItems
        .map((e) => (e['contentDetails']?['videoId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (videoIds.isNotEmpty) {
      final vUri = Uri.https('www.googleapis.com', '/youtube/v3/videos', {
        'part': 'snippet,statistics,contentDetails',
        'id': videoIds.join(','),
        'key': localApiKey,
      });
      final vRes = await http.get(vUri).timeout(const Duration(seconds: 12));
      if (vRes.statusCode == 200) {
        final vItems = (jsonDecode(vRes.body)['items'] as List?) ?? [];
        for (final v in vItems) {
          final vid = v['id'].toString();
          final vsnip = v['snippet'] ?? {};
          final vstats = v['statistics'] ?? {};
          final existingIdx = _localVideos.indexWhere(
            (old) => old['video_id'] == vid,
          );
          final existing = existingIdx >= 0 ? _localVideos[existingIdx] : null;
          final durStr = _parseIsoDuration(
            (v['contentDetails']?['duration'] ?? '').toString(),
          );
          final nextVideo = <String, dynamic>{
            'video_id': vid,
            'channel_id': cid,
            'channel_title': title,
            'channel_thumbnail': thumbUrl,
            'title': (vsnip['title'] ?? 'Untitled').toString(),
            'thumbnail_url':
                ((vsnip['thumbnails']?['high'] ??
                            vsnip['thumbnails']?['medium'])?['url'] ??
                        'https://i.ytimg.com/vi/$vid/hqdefault.jpg')
                    .toString(),
            'published_at':
                (vsnip['publishedAt'] ??
                        DateTime.now().toUtc().toIso8601String())
                    .toString(),
            'view_count':
                int.tryParse((vstats['viewCount'] ?? '0').toString()) ?? 0,
            'like_count':
                int.tryParse((vstats['likeCount'] ?? '0').toString()) ?? 0,
            'duration': durStr,
            'duration_seconds': _durationToSeconds(durStr),
            'views_hp': existing?['views_hp'] ?? 0,
            'views_laptop': existing?['views_laptop'] ?? 0,
            'views_total': existing?['views_total'] ?? 0,
            'watched_count':
                existing?['watched_count'] ?? _getCreatorWatchedCount(cid),
            'is_demo': 0,
            'is_live': (vsnip['liveBroadcastContent'] ?? '').toString() == 'live'
                ? 1
                : 0,
          };
          if (existingIdx >= 0) {
            _localVideos[existingIdx] = nextVideo;
          } else {
            _localVideos.add(nextVideo);
          }
        }
      }
    }
    await _saveStandaloneData();
  }

  String _parseIsoDuration(String iso) {
    final reg = RegExp(
      r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    );
    final m = reg.firstMatch(iso.trim());
    if (m == null) return '';
    if (m.group(1) == null &&
        m.group(2) == null &&
        m.group(3) == null &&
        m.group(4) == null) {
      return '';
    }
    final d = int.tryParse(m.group(1) ?? '0') ?? 0;
    final h = int.tryParse(m.group(2) ?? '0') ?? 0;
    final mins = int.tryParse(m.group(3) ?? '0') ?? 0;
    final s = int.tryParse(m.group(4) ?? '0') ?? 0;
    final totalH = d * 24 + h;
    if (totalH > 0) {
      return '$totalH:${mins.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$mins:${s.toString().padLeft(2, '0')}';
  }

  int _durationToSeconds(String dur) {
    if (dur.isEmpty) return 0;
    final parts = dur.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length == 2) return parts[0] * 60 + parts[1];
    return parts.isNotEmpty ? parts[0] : 0;
  }

  String _formatMinutesLabel(int mins, {bool isMax = false}) {
    if (isMax && mins >= 120) return '2 Jam+ (Tanpa Batas)';
    if (mins == 0) return '0 menit';
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return m == 0 ? '$h jam' : '$h jam $m menit';
    }
    return '$mins menit';
  }

  String _formatCompactNumber(int num) {
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    }
    if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    }
    return num.toString();
  }

  String _formatTimeAgo(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inDays >= 365) {
        final years = (diff.inDays / 365).floor();
        return '$years tahun lalu';
      }
      if (diff.inDays >= 30) {
        final months = (diff.inDays / 30).floor();
        return '$months bulan lalu';
      }
      if (diff.inDays >= 1) {
        return '${diff.inDays} hari lalu';
      }
      if (diff.inHours >= 1) {
        return '${diff.inHours} jam lalu';
      }
      if (diff.inMinutes >= 1) {
        return '${diff.inMinutes} menit lalu';
      }
      return 'Baru saja';
    } catch (_) {
      return isoDate;
    }
  }

  void _sortChannelsByWatchedDesc(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final wa = int.tryParse((a['watched_count'] ?? 0).toString()) ?? 0;
      final wb = int.tryParse((b['watched_count'] ?? 0).toString()) ?? 0;
      if (wb != wa) return wb.compareTo(wa);
      final ta = (a['title'] ?? '').toString().toLowerCase();
      final tb = (b['title'] ?? '').toString().toLowerCase();
      return ta.compareTo(tb);
    });
  }

  int _getCreatorWatchedCount(String channelId, [Map<String, dynamic>? v]) {
    for (final c in channels) {
      if ((c['channel_id'] ?? '').toString() == channelId) {
        return int.tryParse((c['watched_count'] ?? 0).toString()) ?? 0;
      }
    }
    if (v != null) {
      return int.tryParse((v['watched_count'] ?? 0).toString()) ?? 0;
    }
    return 0;
  }

  void _mergeUsageCounts(
    Map<String, dynamic> current,
    Map<String, dynamic> saved, {
    bool isChannel = false,
  }) {
    final currentHp = int.tryParse((current['views_hp'] ?? 0).toString()) ?? 0;
    final savedHp = int.tryParse((saved['views_hp'] ?? 0).toString()) ?? 0;
    final currentLaptop =
        int.tryParse((current['views_laptop'] ?? 0).toString()) ?? 0;
    final savedLaptop =
        int.tryParse((saved['views_laptop'] ?? 0).toString()) ?? 0;
    final hp = currentHp > savedHp ? currentHp : savedHp;
    final laptop = currentLaptop > savedLaptop ? currentLaptop : savedLaptop;
    current['views_hp'] = hp;
    current['views_laptop'] = laptop;
    current['views_total'] = hp + laptop;
    if (isChannel) current['watched_count'] = hp + laptop;
    saved['views_hp'] = hp;
    saved['views_laptop'] = laptop;
    saved['views_total'] = hp + laptop;
    if (isChannel) saved['watched_count'] = hp + laptop;
    if (!isChannel) {
      final currentWatched =
          int.tryParse((current['watched_count'] ?? 0).toString()) ?? 0;
      final savedWatched =
          int.tryParse((saved['watched_count'] ?? 0).toString()) ?? 0;
      final watched = currentWatched > savedWatched
          ? currentWatched
          : savedWatched;
      current['watched_count'] = watched;
      saved['watched_count'] = watched;
    }
  }

  Future<void> _saveWatchCountsLocally(String channelId, String videoId) async {
    if (!_isHpDevice) return;
    try {
      final db = await _openStandaloneDatabase();
      Map<String, dynamic>? channel;
      for (final item in _localChannels) {
        if ((item['channel_id'] ?? '').toString() == channelId) {
          channel = item;
          break;
        }
      }
      if (channel == null) {
        for (final item in channels) {
          if ((item['channel_id'] ?? '').toString() == channelId) {
            channel = Map<String, dynamic>.from(item);
            _localChannels.add(channel);
            break;
          }
        }
      }
      if (channel != null) {
        await db.insert('channels', {
          'id': channelId,
          'data': jsonEncode(channel),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      Map<String, dynamic>? video;
      for (final item in _localVideos) {
        if ((item['video_id'] ?? '').toString() == videoId) {
          video = item;
          break;
        }
      }
      if (video == null) {
        for (final item in videos) {
          if ((item['video_id'] ?? '').toString() == videoId) {
            video = Map<String, dynamic>.from(item);
            _localVideos.add(video);
            break;
          }
        }
      }
      if (video != null) {
        await db.insert('videos', {
          'id': videoId,
          'data': jsonEncode(video),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } catch (_) {}
  }

  Future<void> _openYouTubeVideo(Map<String, dynamic> video) async {
    final channelId = (video['channel_id'] ?? '').toString();
    final videoId = (video['video_id'] ?? '').toString();
    final isHp = _isHpDevice;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    setState(() {
      void updateChannelViews(Map<String, dynamic> c) {
        final hp = int.tryParse((c['views_hp'] ?? 0).toString()) ?? 0;
        final lap = int.tryParse((c['views_laptop'] ?? 0).toString()) ?? 0;
        final newHp = isHp ? hp + 1 : hp;
        final newLap = isHp ? lap : lap + 1;
        c['views_hp'] = newHp;
        c['views_laptop'] = newLap;
        c['views_total'] = newHp + newLap;
        c['watched_count'] = newHp + newLap;
        c['updated_at'] = nowIso;
      }

      void updateVideoViews(Map<String, dynamic> v) {
        final hp = int.tryParse((v['views_hp'] ?? 0).toString()) ?? 0;
        final lap = int.tryParse((v['views_laptop'] ?? 0).toString()) ?? 0;
        final newHp = isHp ? hp + 1 : hp;
        final newLap = isHp ? lap : lap + 1;
        v['views_hp'] = newHp;
        v['views_laptop'] = newLap;
        v['views_total'] = newHp + newLap;
        v['updated_at'] = nowIso;
      }

      if (channelId.isNotEmpty) {
        for (final c in channels) {
          if ((c['channel_id'] ?? '').toString() == channelId) {
            updateChannelViews(c);
          }
        }
        for (final c in _localChannels) {
          if ((c['channel_id'] ?? '').toString() == channelId) {
            updateChannelViews(c);
          }
        }
        _sortChannelsByWatchedDesc(channels);
        _sortChannelsByWatchedDesc(_localChannels);
      }

      if (videoId.isNotEmpty) {
        for (final v in videos) {
          if ((v['video_id'] ?? '').toString() == videoId) {
            updateVideoViews(v);
          }
        }
        for (final v in _localVideos) {
          if ((v['video_id'] ?? '').toString() == videoId) {
            updateVideoViews(v);
          }
        }
      }

      if (channelId.isNotEmpty) {
        for (final displayed in channels) {
          if ((displayed['channel_id'] ?? '').toString() != channelId) continue;
          for (final saved in _localChannels) {
            if ((saved['channel_id'] ?? '').toString() == channelId) {
              _mergeUsageCounts(saved, displayed, isChannel: true);
              break;
            }
          }
        }
      }
      if (videoId.isNotEmpty) {
        for (final displayed in videos) {
          if ((displayed['video_id'] ?? '').toString() != videoId) continue;
          for (final saved in _localVideos) {
            if ((saved['video_id'] ?? '').toString() == videoId) {
              _mergeUsageCounts(saved, displayed);
              break;
            }
          }
        }
      }
    });

    await _saveWatchCountsLocally(channelId, videoId);

    if (!isStandaloneMode && videoId.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(
                '$baseUrl/api/videos/${Uri.encodeComponent(videoId)}/watch',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'device': _deviceType,
                'channel_id': channelId,
                'video_id': videoId,
              }),
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    String rawId = (video['video_id'] ?? '').toString();
    if (rawId.startsWith('demo_') && rawId.length > 8) {
      final parts = rawId.split('_');
      if (parts.length >= 3) {
        rawId = parts.sublist(2).join('_');
      }
    }
    final url = Uri.parse('https://www.youtube.com/watch?v=$rawId');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  final Map<String, String> _transcriptCache = {};
  bool _useTubeTranscript = false;

  Uri _tubeTranscriptUri(String videoId) {
    final rawId = _extractRawVideoId(videoId);
    return Uri.parse('https://tubetranscript.com/id/watch?v=$rawId');
  }

  String _extractRawVideoId(String videoId) {
    var rawId = videoId.trim();
    if (rawId.startsWith('demo_') && rawId.length > 8) {
      final parts = rawId.split('_');
      if (parts.length >= 3) {
        rawId = parts.sublist(2).join('_');
      }
    }
    return rawId;
  }

  String? _extractJsonArrayAfterKey(String source, String key) {
    final keyIdx = source.indexOf(key);
    if (keyIdx < 0) return null;
    var start = source.indexOf('[', keyIdx + key.length);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < source.length; i++) {
      final ch = source.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == 92 /* \ */ && inString) {
        escaped = true;
        continue;
      }
      if (ch == 34 /* " */ ) {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (ch == 91 /* [ */ ) {
          depth++;
        } else if (ch == 93 /* ] */ ) {
          depth--;
          if (depth == 0) {
            return source.substring(start, i + 1);
          }
        }
      }
    }
    return null;
  }

  String _decodeHtmlEntities(String input) {
    var text = input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    return text;
  }

  Map<String, dynamic>? _pickBestCaptionTrack(List<dynamic> tracks) {
    if (tracks.isEmpty) return null;
    for (final lang in ['id', 'en']) {
      for (final t in tracks) {
        if (t is Map) {
          final code = (t['languageCode'] ?? '').toString().toLowerCase();
          if (code == lang || code.startsWith('$lang-')) {
            return Map<String, dynamic>.from(t);
          }
        }
      }
    }
    final first = tracks.first;
    return first is Map ? Map<String, dynamic>.from(first) : null;
  }

  Future<String> _fetchYouTubeTranscriptDirect(
    String rawId,
    void Function(int) onProgress,
  ) async {
    List<dynamic> tracks = [];
    onProgress(20);

    // 1. Coba YouTube Innertube Android API untuk mendapatkan captionTracks
    try {
      final playerRes = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/player'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.google.android.youtube/20.10.38 (Linux; U; Android 14)',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'ANDROID',
                  'clientVersion': '20.10.38',
                  'hl': 'id',
                },
              },
              'videoId': rawId,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (playerRes.statusCode == 200) {
        final data = jsonDecode(playerRes.body);
        final list =
            data['captions']?['playerCaptionsTracklistRenderer']?['captionTracks'];
        if (list is List) tracks = list;
      }
    } catch (_) {}

    onProgress(45);

    // 2. Fallback: ekstrak captionTracks dari halaman watch YouTube (balanced bracket scan)
    if (tracks.isEmpty) {
      final watchRes = await http
          .get(
            Uri.parse('https://www.youtube.com/watch?v=$rawId&hl=id'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125.0 Mobile Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (watchRes.statusCode == 200) {
        final rawArray = _extractJsonArrayAfterKey(
          watchRes.body,
          '"captionTracks":',
        );
        if (rawArray != null) {
          try {
            final parsed = jsonDecode(rawArray);
            if (parsed is List) tracks = parsed;
          } catch (_) {}
        }
      }
    }

    final track = _pickBestCaptionTrack(tracks);
    final baseTrackUrl = (track?['baseUrl'] ?? '').toString();
    if (baseTrackUrl.isEmpty) {
      throw Exception('Video ini tidak menyediakan caption/transkrip.');
    }

    onProgress(70);

    final segments = <String>[];
    // 3. Ambil isi caption (ganti fmt=... ke json3 agar konsisten seperti youtube-transcript-api, lalu fallback XML srv1/srv3)
    try {
      final fmtPattern = RegExp(r'([?&])fmt=[^&]+');
      final json3Url = fmtPattern.hasMatch(baseTrackUrl)
          ? baseTrackUrl.replaceAllMapped(
              fmtPattern,
              (m) => '${m.group(1)}fmt=json3',
            )
          : '$baseTrackUrl&fmt=json3';
      final capRes = await http
          .get(Uri.parse(json3Url))
          .timeout(const Duration(seconds: 12));
      if (capRes.statusCode == 200 && capRes.body.trimLeft().startsWith('{')) {
        final capJson = jsonDecode(capRes.body);
        final events = (capJson['events'] as List?) ?? [];
        for (final ev in events) {
          if (ev is! Map) continue;
          final segs = ev['segs'];
          if (segs is! List) continue;
          final line = segs
              .map((s) => (s is Map ? (s['utf8'] ?? '') : '').toString())
              .join()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (line.isNotEmpty) {
            segments.add(_decodeHtmlEntities(line));
          }
        }
      }
    } catch (_) {}

    if (segments.isEmpty) {
      final xmlRes = await http
          .get(Uri.parse(baseTrackUrl))
          .timeout(const Duration(seconds: 12));
      if (xmlRes.statusCode == 200) {
        final tagRegex = RegExp(
          r'<(?:text|p)\b[^>]*>(.*?)</(?:text|p)>',
          dotAll: true,
        );
        for (final m in tagRegex.allMatches(xmlRes.body)) {
          final rawText = (m.group(1) ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final decoded = _decodeHtmlEntities(rawText).trim();
          if (decoded.isNotEmpty) {
            segments.add(decoded);
          }
        }
      }
    }

    if (segments.isEmpty) {
      throw Exception('Teks transkrip kosong atau tidak tersedia.');
    }
    onProgress(95);
    return segments.join(' ; ');
  }

  Future<String> _fetchTranscriptText(
    String videoId,
    void Function(int) onProgress,
  ) async {
    final rawId = _extractRawVideoId(videoId);
    if (rawId.isEmpty) {
      throw Exception('Video ID tidak valid.');
    }
    final cached = _transcriptCache[rawId];
    if (cached != null && cached.isNotEmpty) {
      onProgress(40);
      await Future.delayed(const Duration(milliseconds: 120));
      onProgress(80);
      await Future.delayed(const Duration(milliseconds: 120));
      onProgress(100);
      return cached;
    }

    onProgress(10);
    String? backendError;
    if (!isStandaloneMode) {
      try {
        final res = await http
            .get(
              Uri.parse(
                '$baseUrl/api/videos/${Uri.encodeComponent(rawId)}/transcript',
              ),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final txt = (data['text'] ?? '').toString().trim();
          if (txt.isNotEmpty) {
            _transcriptCache[rawId] = txt;
            onProgress(100);
            return txt;
          }
        } else {
          try {
            final err = jsonDecode(res.body);
            backendError = (err['detail'] ?? '').toString();
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (kIsWeb && backendError != null && backendError.isNotEmpty) {
      throw Exception(backendError);
    }

    try {
      final directText = await _fetchYouTubeTranscriptDirect(rawId, onProgress);
      _transcriptCache[rawId] = directText;
      onProgress(100);
      return directText;
    } catch (e) {
      if (backendError != null && backendError.isNotEmpty) {
        throw Exception(backendError);
      }
      rethrow;
    }
  }

  Future<String> _buildTranscriptWithPrompt(
    String assetPath,
    String transcriptBody,
  ) async {
    var template = await rootBundle.loadString(assetPath);
    if (template.startsWith('\uFEFF')) {
      template = template.substring(1);
    }
    final placeholder = RegExp(
      r'Teks\s+disini|\[tempel seluruh teks dari awal sampai akhir\]',
      caseSensitive: false,
    );
    if (placeholder.hasMatch(template)) {
      return template.replaceFirst(placeholder, transcriptBody);
    }
    return '${template.trimRight()}\n\nTeks:\n"""\n$transcriptBody\n"""\n';
  }

  Future<void> _showTranscriptPromptDialog(Map<String, dynamic> video) async {
    final videoId = (video['video_id'] ?? '').toString();
    final rawId = _extractRawVideoId(videoId);
    final videoTitle = (video['title'] ?? 'Video YouTube').toString();
    const promptOptions = [
      (
        label: 'Kutip',
        subtitle: 'Bukti kutipan',
        asset: 'assets/prompts/promt kutip.md',
        icon: Icons.format_quote,
        color: Color(0xFFEF5350),
      ),
      (
        label: 'Formal',
        subtitle: 'Tanpa kutipan',
        asset: 'assets/prompts/promt formal.md',
        icon: Icons.description_outlined,
        color: Color(0xFF42A5F5),
      ),
      (
        label: '2.0',
        subtitle: 'Paragraf & poin utuh',
        asset: 'assets/prompts/promt 2.0.md',
        icon: Icons.auto_awesome,
        color: Color(0xFF66BB6A),
      ),
      (
        label: '3.0',
        subtitle: 'Modul lengkap',
        asset: 'assets/prompts/promt 3.0.md',
        icon: Icons.layers,
        color: Color(0xFFAB47BC),
      ),
    ];

    final pasteController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          var step =
              'select'; // 'select' | 'loading' | 'paste' | 'ready' | 'error'
          var progress = 1;
          var selectedLabel = '';
          var selectedAsset = '';
          var compiledResult = '';
          var errorMsg = '';
          var pasteInlineError = '';
          var cancelled = false;
          var pasteBusy = false;
          Timer? smoothTimer;

          void closeDialog() {
            cancelled = true;
            smoothTimer?.cancel();
            Navigator.of(dialogCtx).pop();
          }

          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              Future<void> launchTubeTranscriptPage() async {
                final url = _tubeTranscriptUri(videoId);
                try {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }

              Future<void> openTubeTranscriptForPrompt(
                String label,
                String assetPath,
              ) async {
                smoothTimer?.cancel();
                pasteController.clear();
                setDialogState(() {
                  selectedLabel = label;
                  selectedAsset = assetPath;
                  compiledResult = '';
                  errorMsg = '';
                  pasteInlineError = '';
                  progress = 1;
                  step = 'paste';
                });
                await launchTubeTranscriptPage();
              }

              Future<void> applyPastedTranscript(String rawText) async {
                if (pasteBusy) return;
                pasteBusy = true;
                try {
                  final cleaned = rawText.replaceAll('\r\n', '\n').trim();
                  if (cleaned.isEmpty) {
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      pasteInlineError =
                          'Clipboard masih kosong. Klik "Salin" di TubeTranscript dulu atau tempel manual di kolom bawah.';
                    });
                    return;
                  }
                  final isJustUrl = RegExp(r'^https?://\S+$').hasMatch(cleaned);
                  if (isJustUrl) {
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      pasteInlineError =
                          'Teks yang tersalin masih berupa link URL, bukan isi transkrip.';
                    });
                    return;
                  }
                  if (rawId.isNotEmpty) {
                    _transcriptCache[rawId] = cleaned;
                  }
                  final combined = await _buildTranscriptWithPrompt(
                    selectedAsset,
                    cleaned,
                  );
                  if (cancelled || !ctx.mounted) return;
                  setDialogState(() {
                    progress = 100;
                    compiledResult = combined;
                    pasteInlineError = '';
                    step = 'ready';
                  });
                } finally {
                  pasteBusy = false;
                }
              }

              Future<void> handlePasteButton() async {
                if (pasteBusy) return;
                final manualText = pasteController.text.trim();
                if (manualText.isNotEmpty) {
                  await applyPastedTranscript(manualText);
                  return;
                }
                try {
                  final clipData = await Clipboard.getData(
                    Clipboard.kTextPlain,
                  );
                  await applyPastedTranscript(clipData?.text ?? '');
                } catch (_) {
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    pasteInlineError =
                        'Browser menahan akses clipboard otomatis. Tempel (Ctrl+V) manual ke kolom di bawah lalu tekan Paste Transkrip.';
                  });
                }
              }

              Future<void> startWithPrompt(
                String label,
                String assetPath,
              ) async {
                if (step != 'select') return;
                if (_useTubeTranscript) {
                  await openTubeTranscriptForPrompt(label, assetPath);
                  return;
                }

                smoothTimer?.cancel();
                setDialogState(() {
                  step = 'loading';
                  progress = 1;
                  selectedLabel = label;
                  selectedAsset = assetPath;
                  compiledResult = '';
                  errorMsg = '';
                });

                smoothTimer = Timer.periodic(
                  const Duration(milliseconds: 120),
                  (t) {
                    if (cancelled || !ctx.mounted || step != 'loading') {
                      t.cancel();
                      return;
                    }
                    if (progress < 90) {
                      setDialogState(() {
                        progress = (progress + 3).clamp(1, 90);
                      });
                    }
                  },
                );

                try {
                  final transcriptText = await _fetchTranscriptText(videoId, (
                    pct,
                  ) {
                    if (cancelled || !ctx.mounted) return;
                    setDialogState(() {
                      if (pct > progress) progress = pct.clamp(1, 100);
                    });
                  });
                  if (cancelled || !ctx.mounted) return;
                  final combined = await _buildTranscriptWithPrompt(
                    assetPath,
                    transcriptText,
                  );
                  smoothTimer?.cancel();
                  if (cancelled || !ctx.mounted) return;
                  setDialogState(() {
                    progress = 100;
                    compiledResult = combined;
                    step = 'ready';
                  });
                } catch (e) {
                  smoothTimer?.cancel();
                  if (cancelled || !ctx.mounted) return;
                  setDialogState(() {
                    errorMsg = e.toString().replaceAll('Exception: ', '');
                    step = 'error';
                  });
                }
              }

              final cachedForVideo = rawId.isNotEmpty
                  ? (_transcriptCache[rawId] ?? '')
                  : '';

              return Dialog(
                backgroundColor: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF333333)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header dengan tombol silang (X) di kanan atas
                        Row(
                          children: [
                            const Icon(
                              Icons.subtitles_outlined,
                              color: Color(0xFFFF0033),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Transkrip + Prompt',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    videoTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Tutup / Batal',
                              onPressed: closeDialog,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF2D2D2D), height: 16),
                        if (step == 'select') ...[
                          const Text(
                            'Pilih jenis prompt untuk mengambil & menyalin transkrip:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              final nextVal = !_useTubeTranscript;
                              if (mounted) {
                                setState(() {
                                  _useTubeTranscript = nextVal;
                                });
                              }
                              setDialogState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _useTubeTranscript
                                    ? const Color(0xFF1F2A22)
                                    : const Color(0xFF222222),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _useTubeTranscript
                                      ? const Color(
                                          0xFF66BB6A,
                                        ).withValues(alpha: 0.7)
                                      : const Color(0xFF333333),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Checkbox(
                                      value: _useTubeTranscript,
                                      activeColor: const Color(0xFF2E7D32),
                                      onChanged: (v) {
                                        final nextVal = v ?? false;
                                        if (mounted) {
                                          setState(() {
                                            _useTubeTranscript = nextVal;
                                          });
                                        }
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Gunakan TubeTranscript.com',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          _useTubeTranscript
                                              ? 'Aktif: pilih prompt -> buka tubetranscript.com lalu paste transkrip'
                                              : 'Centang jika YouTube membatasi IP / gagal ambil otomatis',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (
                                var i = 0;
                                i < promptOptions.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => startWithPrompt(
                                      promptOptions[i].label,
                                      promptOptions[i].asset,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF242424),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: promptOptions[i].color
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            promptOptions[i].icon,
                                            color: promptOptions[i].color,
                                            size: 26,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            promptOptions[i].label,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            promptOptions[i].subtitle,
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ] else if (step == 'paste') ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF343434),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Prompt "$selectedLabel" siap diisi dari TubeTranscript',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '1. Di browser TubeTranscript, tunggu transkrip tampil lalu tekan "Salin".\n2. Kembali ke sini lalu tekan tombol "Paste Transkrip".',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.content_paste_go, size: 19),
                            label: const Text(
                              'Paste Transkrip',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: handlePasteButton,
                          ),
                          if (cachedForVideo.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.lightGreenAccent,
                                side: BorderSide(
                                  color: Colors.lightGreenAccent.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.history, size: 17),
                              label: Text(
                                'Pakai Transkrip Tersimpan (${cachedForVideo.length} karakter)',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () =>
                                  applyPastedTranscript(cachedForVideo),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextField(
                            controller: pasteController,
                            minLines: 2,
                            maxLines: 3,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Opsional: tempel manual di sini jika browser memblokir baca clipboard...',
                              hintStyle: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11.5,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF121212),
                              contentPadding: const EdgeInsets.all(10),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF333333),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF42A5F5),
                                ),
                              ),
                            ),
                          ),
                          if (pasteInlineError.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              pasteInlineError,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: launchTubeTranscriptPage,
                                icon: const Icon(Icons.open_in_new, size: 15),
                                label: const Text(
                                  'Buka Ulang',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final ytUrl =
                                      'https://www.youtube.com/watch?v=$rawId';
                                  await Clipboard.setData(
                                    ClipboardData(text: ytUrl),
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Link YouTube disalin ke Clipboard.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.link, size: 15),
                                label: const Text(
                                  'Salin Link YT',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setDialogState(() {
                                    pasteInlineError = '';
                                    step = 'select';
                                  });
                                },
                                child: const Text(
                                  'Kembali',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ] else if (step == 'loading') ...[
                          const SizedBox(height: 16),
                          Center(
                            child: SizedBox(
                              width: 88,
                              height: 88,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 88,
                                    height: 88,
                                    child: CircularProgressIndicator(
                                      value: progress / 100.0,
                                      strokeWidth: 6,
                                      backgroundColor: const Color(0xFF333333),
                                      color: const Color(0xFFFF0033),
                                    ),
                                  ),
                                  Text(
                                    '$progress%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Mengambil transkrip (Prompt $selectedLabel)...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ] else if (step == 'ready') ...[
                          const SizedBox(height: 10),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.lightGreenAccent,
                            size: 46,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Transkrip + Prompt $selectedLabel Siap (100%)',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${compiledResult.length} karakter siap disalin',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text(
                              'Copy',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () async {
                              var copiedOk = false;
                              try {
                                await Clipboard.setData(
                                  ClipboardData(text: compiledResult),
                                );
                                copiedOk = true;
                              } catch (_) {}
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: copiedOk
                                        ? const Color(0xFF1B5E20)
                                        : Colors.orangeAccent,
                                    content: Text(
                                      copiedOk
                                          ? '✅ Transkrip + Prompt $selectedLabel berhasil di-copy ke Clipboard!'
                                          : '⚠️ Gagal menyalin ke Clipboard. Coba ulangi atau izinkan clipboard browser.',
                                    ),
                                  ),
                                );
                              }
                              if (ctx.mounted && copiedOk) {
                                setDialogState(() {
                                  step = 'select';
                                  progress = 1;
                                });
                              }
                            },
                          ),
                        ] else if (step == 'error') ...[
                          const SizedBox(height: 8),
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 42,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            errorMsg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Buka via TubeTranscript.com'),
                            onPressed: () async {
                              if (mounted) {
                                setState(() {
                                  _useTubeTranscript = true;
                                });
                              }
                              await openTubeTranscriptForPrompt(
                                selectedLabel,
                                selectedAsset,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF444444)),
                            ),
                            onPressed: () {
                              setDialogState(() {
                                step = 'select';
                                progress = 1;
                              });
                            },
                            child: const Text('Kembali ke Pilihan Prompt'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      pasteController.dispose();
    }
  }

  bool _isHiddenFlag(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = (raw ?? '').toString().trim().toLowerCase();
    return s == '1' || s == 'true';
  }

  bool _isChannelHidden(String channelId, [Map<String, dynamic>? item]) {
    for (final c in channels) {
      if ((c['channel_id'] ?? '').toString() == channelId) {
        return _isHiddenFlag(c['is_hidden']);
      }
    }
    for (final c in _localChannels) {
      if ((c['channel_id'] ?? '').toString() == channelId) {
        return _isHiddenFlag(c['is_hidden']);
      }
    }
    if (item != null) {
      return _isHiddenFlag(item['channel_is_hidden'] ?? item['is_hidden']);
    }
    return false;
  }

  bool _matchesHideFilter(bool isHidden) {
    if (hideFilter == 'hide') return isHidden;
    if (hideFilter == 'both') return true;
    return !isHidden; // default 'unhide'
  }

  Widget _buildHiddenBadge({Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD600),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'H',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          height: 1.1,
        ),
      ),
    );
  }

  Future<void> _toggleChannelHidden(
    String channelId,
    String channelTitle, {
    required bool hide,
  }) async {
    if (channelId.isEmpty) return;
    final hiddenInt = hide ? 1 : 0;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    setState(() {
      for (final c in _localChannels) {
        if ((c['channel_id'] ?? '').toString() == channelId) {
          c['is_hidden'] = hiddenInt;
          c['hidden_updated_at'] = nowIso;
        }
      }
      for (final c in channels) {
        if ((c['channel_id'] ?? '').toString() == channelId) {
          c['is_hidden'] = hiddenInt;
          c['hidden_updated_at'] = nowIso;
        }
      }
      for (final v in _localVideos) {
        if ((v['channel_id'] ?? '').toString() == channelId) {
          v['channel_is_hidden'] = hiddenInt;
        }
      }
      for (final v in videos) {
        if ((v['channel_id'] ?? '').toString() == channelId) {
          v['channel_is_hidden'] = hiddenInt;
        }
      }
      if (selectedChannelId == channelId && !_matchesHideFilter(hide)) {
        selectedChannelId = '';
      }
      currentPage = 1;
    });

    if (isStandaloneMode || _isHpDevice) {
      await _saveStandaloneData();
    }

    if (!isStandaloneMode) {
      try {
        await http.post(
          Uri.parse(
            '$baseUrl/api/channels/${Uri.encodeComponent(channelId)}/hide',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'hidden': hide}),
        );
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF272727),
        duration: const Duration(seconds: 2),
        content: Text(
          hide
              ? '🟨 "$channelTitle" berhasil di-Hide'
              : '👁️ "$channelTitle" berhasil di-Unhide',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
    await _fetchVideos();
  }

  bool get _isFastUnsubscribeActive =>
      skipUnsubscribeConfirmUntil != null &&
      DateTime.now().isBefore(skipUnsubscribeConfirmUntil!);

  Future<void> _executeUnsubscribe(
    String channelId,
    String channelTitle,
  ) async {
    _localUnsubscribedIds.add(channelId);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    // Update status menjadi 'unfollowed' dengan timestamp terbaru untuk rekonsiliasi sync
    setState(() {
      for (final c in _localChannels) {
        if ((c['channel_id'] ?? '').toString() == channelId) {
          c['status'] = 'unfollowed';
          c['updated_at'] = nowIso;
        }
      }
      channels.removeWhere((c) => c['channel_id'] == channelId);
      videos.removeWhere((v) => v['channel_id'] == channelId);
      _localVideos.removeWhere((v) => v['channel_id'] == channelId);
      if (selectedChannelId == channelId) {
        selectedChannelId = '';
      }
      currentPage = 1;
    });

    if (isStandaloneMode || _isHpDevice) {
      await _saveStandaloneData();
    }

    if (!isStandaloneMode) {
      try {
        await http.post(
          Uri.parse(
            '$baseUrl/api/channels/${Uri.encodeComponent(channelId)}/unfollow',
          ),
        );
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF272727),
        duration: const Duration(seconds: 2),
        content: Text(
          _isFastUnsubscribeActive
              ? '🔕 Unsubscribe "$channelTitle" berhasil (Mode Cepat 10 Menit Aktif)'
              : '🔕 Berhasil Unsubscribe "$channelTitle"',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
    _fetchVideos();
  }

  Future<void> _confirmOrUnsubscribeChannel(
    String channelId,
    String channelTitle,
  ) async {
    if (channelId.isEmpty) return;

    // Jika masih dalam masa 10 menit bebas notifikasi, langsung Unsubscribe!
    if (_isFastUnsubscribeActive) {
      await _executeUnsubscribe(channelId, channelTitle);
      return;
    }

    bool skipNext10Min = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF212121),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              const Icon(Icons.person_remove_alt_1, color: Color(0xFFFF0033)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Unsubscribe "$channelTitle"?',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apakah kamu yakin ingin menghapus / unsubscribe kreator "$channelTitle"? Semua video dari channel ini akan dihapus dari daftar tontonanmu.',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      setModalState(() => skipNext10Min = !skipNext10Min),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: skipNext10Min
                            ? const Color(0xFFFF0033)
                            : const Color(0xFF383838),
                      ),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: skipNext10Min,
                          activeColor: const Color(0xFFFF0033),
                          onChanged: (val) =>
                              setModalState(() => skipNext10Min = val ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'Selama 10 menit ke depan, jangan tanya lagi (langsung Unsubscribe otomatis setiap klik)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Batal',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_remove, size: 18),
              label: const Text('Ya, Unsubscribe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0033),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (skipNext10Min) {
                  setState(() {
                    skipUnsubscribeConfirmUntil = DateTime.now().add(
                      const Duration(minutes: 10),
                    );
                  });
                }
                Navigator.pop(ctx);
                _executeUnsubscribe(channelId, channelTitle);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUsbSyncDialog() async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.usb, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text(
                'Sync USB (HP ⇄ Laptop)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isHpDevice
                          ? Icons.phone_android
                          : Icons.laptop_chromebook,
                      color: Colors.amberAccent,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Perangkat ini: ${_isHpDevice ? "📱 HP Android" : "💻 Laptop / Desktop"}\n• Tulis: views_${_isHpDevice ? "hp" : "laptop"}\n• Terima: views_${_isHpDevice ? "laptop" : "hp"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Hubungkan kabel USB dari HP ke Laptop, lalu klik tombol di bawah:',
                style: TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00838F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.bolt, color: Colors.yellowAccent),
                  label: const Text(
                    '⚡ Sync Langsung Kabel USB',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _performDirectUsbSync();
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(
                        Icons.download,
                        size: 16,
                        color: Colors.greenAccent,
                      ),
                      label: const Text(
                        'Export JSON',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _exportSyncJson();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(
                        Icons.upload,
                        size: 16,
                        color: Colors.orangeAccent,
                      ),
                      label: const Text(
                        'Import JSON',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _importSyncJson();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Tutup',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performDirectUsbSync() async {
    if (syncingUsb) return;
    setState(() {
      syncingUsb = true;
      usbSyncProgress = 15;
      usbSyncReadyGreen = false;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => usbSyncProgress = 30);

      final payload = {
        'device': _deviceType,
        'videos': [
          for (final v in (_localVideos.isNotEmpty ? _localVideos : videos))
            if ((int.tryParse((v['views_hp'] ?? 0).toString()) ?? 0) > 0 ||
                (int.tryParse((v['views_laptop'] ?? 0).toString()) ?? 0) > 0)
              {
                'video_id': v['video_id'],
                'views_hp': v['views_hp'] ?? 0,
                'views_laptop': v['views_laptop'] ?? 0,
                'updated_at':
                    v['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
              },
        ],
        'channels': [
          for (final c
              in (_localChannels.isNotEmpty ? _localChannels : channels))
            {
              'channel_id': c['channel_id'],
              'title': c['title'],
              'handle': c['handle'] ?? '',
              'views_hp': c['views_hp'] ?? 0,
              'views_laptop': c['views_laptop'] ?? 0,
              'status': c['status'] ?? 'subscribed',
              'is_hidden': _isHiddenFlag(c['is_hidden']) ? 1 : 0,
              'hidden_updated_at': (c['hidden_updated_at'] ?? '').toString(),
              'updated_at':
                  c['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
            },
        ],
      };

      if (!mounted) return;
      setState(() => usbSyncProgress = 50);

      http.Response? syncResp;
      final candidates = <String>{
        baseUrl,
        'http://127.0.0.1:8000',
        'http://10.0.2.2:8000',
        'http://172.18.164.232:8000',
        'http://192.168.68.54:8000',
      };
      for (final cand in candidates) {
        try {
          final r = await http
              .post(
                Uri.parse('$cand/api/sync/exchange'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 5));
          if (r.statusCode == 200) {
            baseUrl = cand;
            syncResp = r;
            break;
          }
        } catch (_) {}
      }

      if (syncResp != null && syncResp.statusCode == 200) {
        if (!mounted) return;
        setState(() => usbSyncProgress = 75);

        final data = jsonDecode(syncResp.body);
        final remoteVids = (data['videos'] as List?) ?? [];
        final remoteChs = (data['channels'] as List?) ?? [];

        final remoteVidMap = {
          for (final v in remoteVids) (v['video_id'] ?? '').toString(): v,
        };
        for (final v in _localVideos) {
          final vid = (v['video_id'] ?? '').toString();
          if (remoteVidMap.containsKey(vid)) {
            final rv = remoteVidMap[vid];
            final rHp = int.tryParse((rv['views_hp'] ?? 0).toString()) ?? 0;
            final rLap =
                int.tryParse((rv['views_laptop'] ?? 0).toString()) ?? 0;
            final curHp = int.tryParse((v['views_hp'] ?? 0).toString()) ?? 0;
            final curLap =
                int.tryParse((v['views_laptop'] ?? 0).toString()) ?? 0;
            final nextHp = curHp > rHp ? curHp : rHp;
            final nextLap = curLap > rLap ? curLap : rLap;
            v['views_hp'] = nextHp;
            v['views_laptop'] = nextLap;
            v['views_total'] = nextHp + nextLap;
          }
        }

        for (final rc in remoteChs) {
          final cid = (rc['channel_id'] ?? '').toString();
          if (cid.isEmpty) continue;
          Map<String, dynamic>? cached;
          for (final c in _localChannels) {
            if ((c['channel_id'] ?? '').toString() == cid) {
              cached = c;
              break;
            }
          }
          final rcHp = int.tryParse((rc['views_hp'] ?? 0).toString()) ?? 0;
          final rcLap = int.tryParse((rc['views_laptop'] ?? 0).toString()) ?? 0;
          if (cached == null) {
            // Keep the laptop's creator list available on the phone after
            // disconnecting, instead of losing creators absent from the seed.
            if ((rc['status'] ?? 'subscribed') != 'unfollowed') {
              final added = Map<String, dynamic>.from(rc);
              added['views_total'] = rcHp + rcLap;
              added['watched_count'] = rcHp + rcLap;
              _localChannels.add(added);
            }
            continue;
          }
          final curHp = int.tryParse((cached['views_hp'] ?? 0).toString()) ?? 0;
          final curLap =
              int.tryParse((cached['views_laptop'] ?? 0).toString()) ?? 0;
          final nextHp = curHp > rcHp ? curHp : rcHp;
          final nextLap = curLap > rcLap ? curLap : rcLap;
          cached['views_hp'] = nextHp;
          cached['views_laptop'] = nextLap;
          cached['views_total'] = nextHp + nextLap;
          cached['watched_count'] = nextHp + nextLap;
          if (rc['status'] != null) cached['status'] = rc['status'];
          if (rc['is_hidden'] != null) {
            cached['is_hidden'] = _isHiddenFlag(rc['is_hidden']) ? 1 : 0;
          }
          if (rc['hidden_updated_at'] != null) {
            cached['hidden_updated_at'] = rc['hidden_updated_at'];
          }
          if (rc['updated_at'] != null) cached['updated_at'] = rc['updated_at'];
          if (rc['title'] != null) cached['title'] = rc['title'];
          if (rc['thumbnail_url'] != null) {
            cached['thumbnail_url'] = rc['thumbnail_url'];
          }
        }

        _sortChannelsByWatchedDesc(_localChannels);
        _sortChannelsByWatchedDesc(channels);

        if (!mounted) return;
        setState(() => usbSyncProgress = 90);

        await _fetchVideos(silent: true);
        // USB sync updates the in-memory cache. Persist it before reporting
        // success, otherwise the next cold start restores stale creator counts.
        await _saveStandaloneData();

        if (!mounted) return;
        setState(() {
          usbSyncProgress = 100;
          syncingUsb = false;
          usbSyncReadyGreen = true;
        });

        _usbSyncResetTimer?.cancel();
        _usbSyncResetTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => usbSyncReadyGreen = false);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B5E20),
            content: Text(
              '⚡ Sync USB 100% Selesai! Data HP & Laptop terhubung (${remoteVids.length} video, ${remoteChs.length} channel).',
            ),
          ),
        );
      } else {
        throw Exception(
          'Tidak dapat terhubung ke Laptop via kabel USB. Pastikan backend di laptop menyala.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        syncingUsb = false;
        usbSyncProgress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            '⚠️ Gagal Sync USB: ${e.toString().replaceAll("Exception: ", "")}',
          ),
        ),
      );
    }
  }

  Future<void> _exportSyncJson() async {
    final payload = {
      'device': _deviceType,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'videos': [
        for (final v in (_localVideos.isNotEmpty ? _localVideos : videos))
          if ((int.tryParse((v['views_hp'] ?? 0).toString()) ?? 0) > 0 ||
              (int.tryParse((v['views_laptop'] ?? 0).toString()) ?? 0) > 0)
            {
              'video_id': v['video_id'],
              'views_hp': v['views_hp'] ?? 0,
              'views_laptop': v['views_laptop'] ?? 0,
              'updated_at':
                  v['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
            },
      ],
      'channels': [
        for (final c in (_localChannels.isNotEmpty ? _localChannels : channels))
          {
            'channel_id': c['channel_id'],
            'title': c['title'],
            'handle': c['handle'] ?? '',
            'views_hp': c['views_hp'] ?? 0,
            'views_laptop': c['views_laptop'] ?? 0,
            'status': c['status'] ?? 'subscribed',
            'is_hidden': _isHiddenFlag(c['is_hidden']) ? 1 : 0,
            'hidden_updated_at': (c['hidden_updated_at'] ?? '').toString(),
            'updated_at':
                c['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
          },
      ],
    };
    final jsonStr = jsonEncode(payload);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1B5E20),
          content: Text(
            '📋 Paket data sync (.json) berhasil disalin ke Clipboard!',
          ),
        ),
      );
    }
  }

  Future<void> _importSyncJson() async {
    final ctrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Import Paket Data Sync',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tempelkan isi JSON data sync dari perangkat lain:',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    maxLines: 6,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          '{"device": "...", "videos": [...], "channels": [...]}',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                      filled: true,
                      fillColor: Color(0xFF282828),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0033),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _applySyncDataString(ctrl.text);
                },
                child: const Text('Terapkan Sync'),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _applySyncDataString(String rawJson) async {
    try {
      final data = jsonDecode(rawJson.trim());
      final remoteVids = (data['videos'] as List?) ?? [];
      final remoteChs = (data['channels'] as List?) ?? [];
      final remoteVidMap = {
        for (final v in remoteVids) (v['video_id'] ?? '').toString(): v,
      };
      final remoteChMap = {
        for (final c in remoteChs) (c['channel_id'] ?? '').toString(): c,
      };

      final localChIds = <String>{
        for (final c in _localChannels) (c['channel_id'] ?? '').toString(),
      };

      if (!mounted) return;
      setState(() {
        for (final v in _localVideos) {
          final vid = (v['video_id'] ?? '').toString();
          if (remoteVidMap.containsKey(vid)) {
            final rv = remoteVidMap[vid];
            final rHp = int.tryParse((rv['views_hp'] ?? 0).toString()) ?? 0;
            final rLap =
                int.tryParse((rv['views_laptop'] ?? 0).toString()) ?? 0;
            final curHp = int.tryParse((v['views_hp'] ?? 0).toString()) ?? 0;
            final curLap =
                int.tryParse((v['views_laptop'] ?? 0).toString()) ?? 0;
            final nextHp = curHp > rHp ? curHp : rHp;
            final nextLap = curLap > rLap ? curLap : rLap;
            v['views_hp'] = nextHp;
            v['views_laptop'] = nextLap;
            v['views_total'] = nextHp + nextLap;
          }
        }
        for (final c in _localChannels) {
          final cid = (c['channel_id'] ?? '').toString();
          if (remoteChMap.containsKey(cid)) {
            final rc = remoteChMap[cid];
            final rHp = int.tryParse((rc['views_hp'] ?? 0).toString()) ?? 0;
            final rLap =
                int.tryParse((rc['views_laptop'] ?? 0).toString()) ?? 0;
            final curHp = int.tryParse((c['views_hp'] ?? 0).toString()) ?? 0;
            final curLap =
                int.tryParse((c['views_laptop'] ?? 0).toString()) ?? 0;
            final nextHp = curHp > rHp ? curHp : rHp;
            final nextLap = curLap > rLap ? curLap : rLap;
            c['views_hp'] = nextHp;
            c['views_laptop'] = nextLap;
            c['views_total'] = nextHp + nextLap;
            c['watched_count'] = nextHp + nextLap;
            if (rc['status'] != null) c['status'] = rc['status'];
            if (rc['is_hidden'] != null) {
              final hasHidKey = rc.containsKey('hidden_updated_at');
              final inHidTs = (rc['hidden_updated_at'] ?? '').toString().trim();
              final exHidTs = (c['hidden_updated_at'] ?? '').toString().trim();
              final effIn = hasHidKey
                  ? inHidTs
                  : (rc['updated_at'] ?? '').toString().trim();
              final effEx = hasHidKey
                  ? exHidTs
                  : (exHidTs.isNotEmpty
                        ? exHidTs
                        : (c['updated_at'] ?? '').toString().trim());
              if (_isNewerOrEqualIso(effIn, effEx)) {
                c['is_hidden'] = _isHiddenFlag(rc['is_hidden']) ? 1 : 0;
                if (effIn.isNotEmpty) {
                  c['hidden_updated_at'] = effIn;
                }
              }
            }
          }
        }
        for (final entry in remoteChMap.entries) {
          final cid = entry.key;
          if (cid.isNotEmpty &&
              !localChIds.contains(cid) &&
              entry.value is Map) {
            final rc = Map<String, dynamic>.from(entry.value as Map);
            _localChannels.add(rc);
          }
        }
        _sortChannelsByWatchedDesc(_localChannels);
        _sortChannelsByWatchedDesc(channels);
      });

      await _saveStandaloneData();
      if (!mounted) return;
      if (isStandaloneMode) {
        _applyLocalFilterAndPagination();
      } else {
        await _fetchVideos(silent: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1B5E20),
          content: Text(
            '✅ Import sync berhasil! (${remoteVids.length} video, ${remoteChs.length} channel)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ Format JSON tidak valid: $e'),
        ),
      );
    }
  }

  Future<void> _exportExcelCsv() async {
    if (!isStandaloneMode) {
      final url = Uri.parse('$baseUrl/api/channels/export-csv');
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
    // Jika di HP (Mode Mandiri), tampilkan & salin teks CSV siap tempel ke Excel / Google Sheets
    final buffer = StringBuffer(
      'Channel ID,Nama Channel,Handle,Jumlah Video\n',
    );
    for (final c in channels) {
      buffer.writeln(
        '${c['channel_id']},"${c['title']}",${c['handle'] ?? ''},${c['video_count'] ?? 0}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Data CSV berhasil disalin ke Clipboard! Siap ditempel (Paste) ke Excel / Google Sheets.',
        ),
      ),
    );
  }

  Future<void> _showAddChannelModal() async {
    final handleCtrl = TextEditingController();
    final csvCtrl = TextEditingController();
    bool busy = false;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _DisposeOnUnmount(
        onDispose: () {
          handleCtrl.dispose();
          csvCtrl.dispose();
        },
        child: StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            backgroundColor: const Color(0xFF212121),
            title: const Text('Tambah Channel Follower / Import Excel CSV'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '1. Tambah 1 Channel (@handle, Link Channel, atau ID UC...):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: handleCtrl,
                            decoration: const InputDecoration(
                              hintText:
                                  'Contoh: @FerryIrwandi atau @RadityaDika',
                              filled: true,
                              fillColor: Color(0xFF121212),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF0033),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: busy
                              ? null
                              : () async {
                                  setModalState(() {
                                    busy = true;
                                    modalError = null;
                                  });
                                  try {
                                    if (isStandaloneMode) {
                                      await _standaloneAddAndSyncChannel(
                                        handleCtrl.text,
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        _applyLocalFilterAndPagination();
                                      }
                                    } else {
                                      final res = await http
                                          .post(
                                            Uri.parse('$baseUrl/api/channels'),
                                            headers: {
                                              'Content-Type':
                                                  'application/json',
                                            },
                                            body: jsonEncode({
                                              'identifier': handleCtrl.text,
                                            }),
                                          )
                                          .timeout(const Duration(seconds: 25));
                                      if (res.statusCode == 200) {
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (mounted) _refreshAll();
                                      } else {
                                        String detail =
                                            'Gagal menambah channel';
                                        try {
                                          final err = jsonDecode(res.body);
                                          detail = (err['detail'] ?? detail)
                                              .toString();
                                        } catch (_) {}
                                        if (ctx.mounted) {
                                          setModalState(() {
                                            modalError = detail;
                                            busy = false;
                                          });
                                        }
                                      }
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setModalState(() {
                                        modalError = e.toString().replaceAll(
                                          'Exception: ',
                                          '',
                                        );
                                        busy = false;
                                      });
                                    }
                                  }
                                },
                          child: const Text('Tambah'),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    const Text(
                      '2. Atau Paste Banyak Channel dari Excel / CSV (1 baris per channel):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Bisa paste daftar @handle atau isi file subscriptions.csv dari YouTube:',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: csvCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText:
                            '@FajrulFx\n@FerryIrwandi\n@RadityaDika\natau UCxxxx,https://...,Nama Channel',
                        filled: true,
                        fillColor: Color(0xFF121212),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        modalError!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import Daftar CSV'),
                onPressed: busy
                    ? null
                    : () async {
                        setModalState(() {
                          busy = true;
                          modalError = null;
                        });
                        try {
                          if (isStandaloneMode) {
                            for (final line in csvCtrl.text.split('\n')) {
                              final trimmed = line.trim();
                              if (trimmed.isEmpty) continue;
                              final cols = trimmed.split(',');
                              final first = cols[0].trim();
                              if (first.isEmpty) continue;
                              if (first.startsWith('UC') && cols.length >= 2) {
                                final cid = first;
                                final col1 = cols[1].trim();
                                final col2 = cols.length >= 3
                                    ? cols[2].trim()
                                    : '';
                                final title = col1.startsWith('http')
                                    ? (col2.isNotEmpty ? col2 : cid)
                                    : (col1.isNotEmpty
                                          ? col1
                                          : (col2.isNotEmpty ? col2 : cid));
                                _localUnsubscribedIds.remove(cid);
                                _localChannels.removeWhere(
                                  (c) => c['channel_id'] == cid,
                                );
                                _localChannels.add({
                                  'channel_id': cid,
                                  'title': title,
                                  'handle': col2.startsWith('@') ? col2 : '',
                                  'thumbnail_url': '',
                                  'uploads_playlist_id':
                                      'UU${cid.substring(2)}',
                                  'source': 'csv',
                                  'video_count': 0,
                                  'status': 'subscribed',
                                });
                              } else if (localApiKey.isNotEmpty) {
                                try {
                                  await _standaloneAddAndSyncChannel(first);
                                } catch (_) {}
                              }
                            }
                            await _saveStandaloneData();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) _applyLocalFilterAndPagination();
                            return;
                          }
                          final res = await http
                              .post(
                                Uri.parse('$baseUrl/api/channels/import-csv'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({'csv_text': csvCtrl.text}),
                              )
                              .timeout(const Duration(seconds: 30));
                          if (res.statusCode == 200) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) _refreshAll();
                          } else {
                            String detail = 'Gagal import CSV';
                            try {
                              final err = jsonDecode(res.body);
                              detail = (err['detail'] ?? detail).toString();
                            } catch (_) {}
                            if (ctx.mounted) {
                              setModalState(() {
                                modalError = detail;
                                busy = false;
                              });
                            }
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() {
                              modalError = e.toString().replaceAll(
                                'Exception: ',
                                '',
                              );
                              busy = false;
                            });
                          }
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showApiSettingsModal() async {
    final apiKeyCtrl = TextEditingController(text: localApiKey);
    final oauthCtrl = TextEditingController(text: localOauthToken);
    final serverCtrl = TextEditingController(text: baseUrl);
    bool syncing = false;
    String? statusMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _DisposeOnUnmount(
        onDispose: () {
          apiKeyCtrl.dispose();
          oauthCtrl.dispose();
          serverCtrl.dispose();
        },
        child: StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            backgroundColor: const Color(0xFF212121),
            title: const Text(
              'Pengaturan API YouTube (Gratis) & Mode Mandiri HP',
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isStandaloneMode
                            ? const Color(0xFF1B3B2B)
                            : const Color(0xFF1A2B3C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isStandaloneMode
                                ? Icons.phone_android
                                : Icons.computer,
                            color: Colors.greenAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isStandaloneMode
                                  ? 'Mode Mandiri Aktif: Aplikasi jalan sendiri langsung di HP/Perangkat tanpa butuh Backend Python!'
                                  : 'Mode Terhubung Backend Python ($baseUrl)',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💡 Cara Dapat YouTube API Key Gratis (1 Menit, Rp 0):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '1. Buka console.cloud.google.com -> Buat Project baru.\n'
                            '2. Buka menu "APIs & Services" -> "Library" -> Cari "YouTube Data API v3" -> Klik Enable.\n'
                            '3. Buka "Credentials" -> "Create Credentials" -> Pilih "API Key" -> Copy & Paste di bawah.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'YouTube API Key ${hasApiKey ? "(Sudah Terpasang)" : "(Belum Diisi)"}:',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: apiKeyCtrl,
                      decoration: const InputDecoration(
                        hintText: 'AIzaSy...',
                        filled: true,
                        fillColor: Color(0xFF121212),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'OAuth 2.0 Access Token (Opsional - ${localOauthToken.isNotEmpty ? "Sudah Terisi" : "Kosong, Boleh Diabaikan"}):',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: oauthCtrl,
                      decoration: const InputDecoration(
                        hintText:
                            'Kosongkan saja jika sudah pakai API Key (khusus import subscription)',
                        filled: true,
                        fillColor: Color(0xFF121212),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Cukup isi YouTube API Key di atas. OAuth Token hanya diperlukan jika ingin mengimpor daftar subscription akun Google secara otomatis.',
                      style: TextStyle(fontSize: 11.5, color: Colors.white60),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Alamat Server Python (Opsional - kosongkan jika jalan mandiri di HP):',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: serverCtrl,
                      decoration: const InputDecoration(
                        hintText: 'http://127.0.0.1:8000',
                        filled: true,
                        fillColor: Color(0xFF121212),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (statusMsg != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        statusMsg!,
                        style: const TextStyle(color: Colors.greenAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (isStandaloneMode || baseUrl.trim().isEmpty) {
                    _localChannels.removeWhere((c) => c['source'] == 'demo');
                    _localVideos.removeWhere((v) => v['is_demo'] == 1);
                    await _saveStandaloneData();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) _applyLocalFilterAndPagination();
                    return;
                  }
                  try {
                    await http
                        .delete(Uri.parse('$baseUrl/api/demo'))
                        .timeout(const Duration(seconds: 10));
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _refreshAll();
                },
                child: const Text(
                  'Hapus Data Demo',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
              ),
              ElevatedButton(
                onPressed: syncing
                    ? null
                    : () async {
                        final nextKey = apiKeyCtrl.text.trim();
                        final nextOauth = oauthCtrl.text.trim();
                        final nextServer = serverCtrl.text.trim();
                        if (!mounted) return;
                        setState(() {
                          localApiKey = nextKey;
                          localOauthToken = nextOauth;
                          hasApiKey = localApiKey.isNotEmpty;
                          apiKeyPreview = localApiKey.length > 8
                              ? '${localApiKey.substring(0, 6)}...${localApiKey.substring(localApiKey.length - 4)}'
                              : (localApiKey.isNotEmpty ? 'Terpasang' : '');
                          if (nextServer.isEmpty) {
                            baseUrl = '';
                            isStandaloneMode = true;
                          } else {
                            baseUrl = nextServer;
                          }
                        });
                        if (ctx.mounted) {
                          setModalState(() {
                            syncing = true;
                            statusMsg = 'Menyimpan & menyinkronkan video...';
                          });
                        }
                        await _saveStandaloneData();
                        if (!isStandaloneMode && baseUrl.isNotEmpty) {
                          try {
                            if (localApiKey.isNotEmpty ||
                                localOauthToken.isNotEmpty) {
                              await http
                                  .post(
                                    Uri.parse('$baseUrl/api/settings'),
                                    headers: {
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode({
                                      'api_key': localApiKey,
                                      'oauth_token': localOauthToken,
                                    }),
                                  )
                                  .timeout(const Duration(seconds: 10));
                            }
                            await http
                                .post(
                                  Uri.parse('$baseUrl/api/sync'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'import_mode': localOauthToken.isNotEmpty
                                        ? 'subscriptions'
                                        : 'none',
                                    'years_back': 4,
                                  }),
                                )
                                .timeout(const Duration(seconds: 15));
                            if (mounted) {
                              setState(() {
                                refreshingYouTube = true;
                                refreshProgress = 2;
                                refreshReadyGreen = false;
                              });
                              _startRefreshPolling();
                            }
                          } catch (_) {}
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _refreshAll();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0033),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  syncing ? 'Menyinkronkan...' : 'Simpan & Sync Sekarang',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleSidebarMode() {
    final nextMode = sidebarMode == 'full' ? 'hidden' : 'full';
    setState(() => sidebarMode = nextMode);
    _saveUiPreferences(newSidebarMode: nextMode);
  }

  void _selectChannelTab(String cid) {
    final tabKey = cid.isEmpty ? 'home' : cid;
    final savedLimit = tabLimits[tabKey] ?? defaultLimit;
    final isMobileScreen = MediaQuery.of(context).size.width < 750;
    setState(() {
      selectedChannelId = cid;
      if (isMobileScreen && sidebarMode == 'full') {
        sidebarMode = 'hidden';
      }
      limit = (savedLimit == 25 || savedLimit == 50 || savedLimit == 100)
          ? savedLimit
          : 50;
      currentPage = 1;
    });
    if (isMobileScreen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _fetchVideos();
  }

  void _resetHomeAndClearSearch() {
    _searchCtrl.clear();
    searchQuery = '';
    _showMobileSearch = false;
    _selectChannelTab('');
  }

  void _scrollToTop() {
    if (!_videoScrollController.hasClients) return;
    _videoScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleMobileSearch() {
    final willShow = !_showMobileSearch;
    setState(() => _showMobileSearch = willShow);
    if (willShow) {
      if (_videoScrollController.hasClients &&
          _videoScrollController.offset > 0) {
        _videoScrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mobileSearchFocusNode.requestFocus();
      });
    } else {
      _mobileSearchFocusNode.unfocus();
    }
  }

  void _submitSearch([String? value]) {
    setState(() {
      searchQuery = value ?? _searchCtrl.text;
      currentPage = 1;
    });
    _fetchVideos();
  }

  Widget _buildSearchInputBox({
    double height = 40,
    EdgeInsetsGeometry? margin,
    String hintText = 'Cari video...',
    double buttonWidth = 44,
    double leftPad = 14,
    FocusNode? focusNode,
  }) {
    return Container(
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Row(
        children: [
          SizedBox(width: leftPad),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _submitSearch,
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              key: const Key('search_clear_btn'),
              tooltip: 'Kosongkan teks',
              icon: const Icon(Icons.clear, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: () {
                _searchCtrl.clear();
                setState(() {});
                focusNode?.requestFocus();
              },
            ),
          Container(
            width: buttonWidth,
            height: height,
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
            ),
            child: IconButton(
              key: const Key('search_submit_btn'),
              tooltip: 'Cari',
              icon: const Icon(Icons.search, size: 19),
              padding: EdgeInsets.zero,
              onPressed: _submitSearch,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularPercentIndicator(int progress, Color color) {
    final safePct = progress.clamp(0, 100);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            value: safePct > 0 ? (safePct / 100.0) : null,
            strokeWidth: 2.3,
            backgroundColor: Colors.white24,
            color: color,
          ),
        ),
        Text(
          '$safePct%',
          style: TextStyle(
            fontSize: safePct >= 100 ? 7.0 : 8.5,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildUsbSyncButton({required bool isMobile}) {
    final usbLabel = _isHpDevice ? 'Sync Laptop (USB)' : 'Sync HP (USB)';
    if (syncingUsb) {
      return Tooltip(
        message: 'Sync USB: $usbSyncProgress%',
        child: Container(
          width: 40,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF004D40),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.cyanAccent, width: 1.2),
          ),
          child: _buildCircularPercentIndicator(
            usbSyncProgress,
            Colors.cyanAccent,
          ),
        ),
      );
    }

    if (usbSyncReadyGreen) {
      return Tooltip(
        message: '100% Sync Selesai - Klik untuk tampilkan',
        child: SizedBox(
          width: 38,
          height: 34,
          child: ElevatedButton(
            onPressed: _performDirectUsbSync,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              minimumSize: const Size(38, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Icon(
              Icons.check_circle,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: usbLabel,
      child: SizedBox(
        width: 38,
        height: 34,
        child: OutlinedButton(
          onPressed: _performDirectUsbSync,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF00695C)),
            backgroundColor: const Color(0xFF1B2A30),
            padding: EdgeInsets.zero,
            minimumSize: const Size(38, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Icon(Icons.usb, size: 18, color: Colors.cyanAccent),
        ),
      ),
    );
  }

  Widget _buildRefreshYouTubeButton(bool isMobile) {
    final tooltipMsg = refreshingYouTube
        ? 'Refresh YouTube ($refreshProgress%)'
        : (refreshReadyGreen
              ? '100% Siap - Klik untuk tampilkan'
              : 'Refresh YouTube');
    return Tooltip(
      message: tooltipMsg,
      child: SizedBox(
        width: refreshingYouTube ? 40 : 38,
        height: 34,
        child: ElevatedButton(
          onPressed: _manualRefreshYouTube,
          style: ElevatedButton.styleFrom(
            backgroundColor: refreshReadyGreen
                ? const Color(0xFF2E7D32)
                : const Color(0xFFFF0033),
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            minimumSize: const Size(38, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: refreshingYouTube
              ? _buildCircularPercentIndicator(refreshProgress, Colors.white)
              : Icon(
                  refreshReadyGreen ? Icons.check_circle : Icons.refresh,
                  size: 18,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 750;
    final isCompactHeader = screenWidth < 1150;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile
          ? Drawer(
              backgroundColor: const Color(0xFF0F0F0F),
              child: SafeArea(child: _buildSidebar(forceFull: true)),
            )
          : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Material(
          color: const Color(0xFF0F0F0F),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10),
            child: SafeArea(
              child: Align(
                alignment: Alignment.center,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: isMobile
                          ? 'Daftar Channel (Subscriptions)'
                          : 'Tampilkan / Sembunyikan Sidebar',
                      icon: const Icon(Icons.menu, color: Colors.white),
                      padding: isMobile ? EdgeInsets.zero : null,
                      constraints: isMobile
                          ? const BoxConstraints.tightFor(width: 34, height: 34)
                          : null,
                      visualDensity: isMobile
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                      onPressed: () {
                        if (isMobile) {
                          _scaffoldKey.currentState?.openDrawer();
                        } else {
                          _cycleSidebarMode();
                        }
                      },
                    ),
                    Tooltip(
                      message: 'Semua Follower & bersihkan pencarian',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _resetHomeAndClearSearch,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF0033),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: isMobile ? 16 : 18,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Yor',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 12 : 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: isMobile ? 6 : 8),
                    if (!isCompactHeader)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Tooltip(
                          message: 'Semua Follower & bersihkan pencarian',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: _resetHomeAndClearSearch,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                'YouTube Follower',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isMobile)
                      const Spacer()
                    else
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: _buildFilterAndSearchRow(
                            screenWidth: screenWidth,
                            isMobile: false,
                          ),
                        ),
                      ),

                    if (isMobile) ...[
                      Tooltip(
                        message: 'Cari Video',
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: IconButton(
                            key: const Key('mobile_search_toggle'),
                            padding: EdgeInsets.zero,
                            onPressed: _toggleMobileSearch,
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  (_showMobileSearch || searchQuery.isNotEmpty)
                                  ? const Color(0xFF1565C0)
                                  : const Color(0xFF222222),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color:
                                      (_showMobileSearch ||
                                          searchQuery.isNotEmpty)
                                      ? const Color(0xFF42A5F5)
                                      : const Color(0xFF3A3A3A),
                                ),
                              ),
                            ),
                            icon: Icon(
                              _showMobileSearch
                                  ? Icons.search_off
                                  : Icons.search,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildFilterSortButton(height: 34, compact: true),
                      const SizedBox(width: 4),
                    ],

                    if (!isMobile) ...[
                      // 1. Tombol Sync USB (mode layar penuh; pada Android ada di menu ⋮)
                      _buildUsbSyncButton(isMobile: false),
                      const SizedBox(width: 4),
                    ],

                    // 2. Tombol Refresh YouTube
                    _buildRefreshYouTubeButton(isMobile),

                    if (!isMobile) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Export Excel/CSV',
                        child: SizedBox(
                          width: 38,
                          height: 34,
                          child: OutlinedButton(
                            onPressed: _exportExcelCsv,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF303030)),
                              backgroundColor: const Color(0xFF222222),
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(38, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Icon(
                              Icons.table_view,
                              size: 18,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Tambah Channel',
                        child: SizedBox(
                          width: 38,
                          height: 34,
                          child: ElevatedButton(
                            onPressed: _showAddChannelModal,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF272727),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(38, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pengaturan API & Sync',
                        onPressed: _showApiSettingsModal,
                        icon: Icon(
                          Icons.settings,
                          size: 22,
                          color: hasApiKey
                              ? Colors.greenAccent
                              : Colors.amberAccent,
                        ),
                      ),
                    ] else ...[
                      // Pada HP: Menu Popup 3 Titik (Menghilangkan Right Overflow 49px sama sekali!)
                      PopupMenuButton<String>(
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 22,
                        ),
                        tooltip: 'Menu Lainnya',
                        color: const Color(0xFF212121),
                        onSelected: (val) {
                          if (val == 'usb') _performDirectUsbSync();
                          if (val == 'add') _showAddChannelModal();
                          if (val == 'csv') _exportExcelCsv();
                          if (val == 'export_sync') _exportSyncJson();
                          if (val == 'import_sync') _importSyncJson();
                          if (val == 'settings') _showApiSettingsModal();
                        },
                        itemBuilder: (ctx) {
                          final usbTitle = syncingUsb
                              ? 'Sync USB ($usbSyncProgress%)'
                              : (usbSyncReadyGreen
                                    ? '100% Sync Selesai - Tampilkan'
                                    : (_isHpDevice
                                          ? 'Sync Laptop (USB)'
                                          : 'Sync HP (USB)'));
                          final items = <(String, IconData, Color, String)>[
                            (
                              'usb',
                              usbSyncReadyGreen
                                  ? Icons.check_circle
                                  : Icons.usb,
                              usbSyncReadyGreen
                                  ? Colors.greenAccent
                                  : Colors.cyanAccent,
                              usbTitle,
                            ),
                            (
                              'add',
                              Icons.person_add_alt_1,
                              Colors.white,
                              'Tambah Channel',
                            ),
                            (
                              'csv',
                              Icons.table_view,
                              Colors.greenAccent,
                              'Export Excel / CSV',
                            ),
                            (
                              'export_sync',
                              Icons.upload,
                              Colors.cyanAccent,
                              'Salin JSON Sync',
                            ),
                            (
                              'import_sync',
                              Icons.download,
                              Colors.cyanAccent,
                              'Tempel JSON Sync',
                            ),
                            (
                              'settings',
                              Icons.settings,
                              Colors.amberAccent,
                              'Pengaturan API & IP',
                            ),
                          ];
                          return [
                            for (final (value, icon, color, label) in items)
                              PopupMenuItem<String>(
                                value: value,
                                child: Row(
                                  children: [
                                    Icon(icon, size: 18, color: color),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ];
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMobile && sidebarMode != 'hidden') _buildSidebar(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (ctx, constraints) =>
                        _buildVideoGridWithPagination(constraints.maxWidth),
                  ),
          ),
        ],
      ),
      floatingActionButton: Tooltip(
        message: 'Kembali ke atas',
        child: SizedBox(
          width: 38,
          height: 38,
          child: FloatingActionButton(
            key: const Key('scroll_to_top_fab'),
            heroTag: 'scroll_to_top_fab',
            elevation: 0,
            highlightElevation: 0,
            focusElevation: 0,
            hoverElevation: 0,
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFF2196F3), width: 2.0),
            ),
            backgroundColor: Colors.transparent,
            onPressed: _scrollToTop,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar({bool forceFull = false}) {
    final sidebarChannels = channels
        .where((ch) => _matchesHideFilter(_isHiddenFlag(ch['is_hidden'])))
        .toList();
    final sidebarContent = Material(
      color: const Color(0xFF0F0F0F),
      child: _HomeScrollWithBar(
        controller: _sidebarScrollController,
        itemCount: sidebarChannels.length,
        railKey: const Key('sidebar_fast_scrollbar'),
        thumbKey: const Key('sidebar_fast_thumb'),
        itemLabel: 'Channel',
        trackPadding: const EdgeInsets.only(top: 6, right: 2, bottom: 8),
        scrollView: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: CustomScrollView(
            controller: _sidebarScrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _sidebarTile(
                              icon: Icons.home_filled,
                              title:
                                  'Semua Follower (${sidebarChannels.length})',
                              selected: selectedChannelId.isEmpty,
                              onTap: () => _selectChannelTab(''),
                            ),
                          ),
                          if (forceFull)
                            IconButton(
                              tooltip: 'Tutup',
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            )
                          else
                            IconButton(
                              tooltip: 'Sembunyikan Sidebar',
                              icon: const Icon(
                                Icons.keyboard_double_arrow_left,
                                size: 20,
                                color: Colors.white60,
                              ),
                              onPressed: () {
                                setState(() => sidebarMode = 'hidden');
                                _saveUiPreferences(newSidebarMode: 'hidden');
                              },
                            ),
                        ],
                      ),
                      const Divider(color: Color(0xFF272727), height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          'Subscriptions ›',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _buildSidebarLiveSection(isDrawer: forceFull),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final ch = sidebarChannels[index];
                    final cid = (ch['channel_id'] ?? '').toString();
                    final title = (ch['title'] ?? '').toString();
                    final isHidden = _isHiddenFlag(ch['is_hidden']);
                    final cHp =
                        int.tryParse((ch['views_hp'] ?? 0).toString()) ?? 0;
                    final cLap =
                        int.tryParse((ch['views_laptop'] ?? 0).toString()) ?? 0;
                    final watchedCount =
                        int.tryParse(
                          (ch['views_total'] ?? ch['watched_count'] ?? 0)
                              .toString(),
                        ) ??
                        (cHp + cLap);
                    final isSelected = selectedChannelId == cid;
                    return Tooltip(
                      message:
                          '$title${isHidden ? ' (Hidden)' : ''}\nTotal: $watchedCount view (📱 HP: $cHp | 💻 Laptop: $cLap)',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _selectChannelTab(cid),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF272727)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFF383838),
                                backgroundImage:
                                    (ch['thumbnail_url'] ?? '')
                                        .toString()
                                        .isNotEmpty
                                    ? NetworkImage(ch['thumbnail_url'])
                                    : null,
                                onBackgroundImageError:
                                    (ch['thumbnail_url'] ?? '')
                                        .toString()
                                        .isNotEmpty
                                    ? (_, _) {}
                                    : null,
                                child: Text(
                                  title.isNotEmpty ? title[0] : '?',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isHidden) ...[
                                      const SizedBox(width: 6),
                                      _buildHiddenBadge(
                                        key: Key('sidebar_hidden_$cid'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: watchedCount > 0
                                      ? const Color(0xFF1E3A2F)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$watchedCount',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: watchedCount > 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: watchedCount > 0
                                        ? const Color(0xFF81C784)
                                        : Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: sidebarChannels.length),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const Divider(color: Color(0xFF272727), height: 28),
                      _sidebarTile(
                        icon: Icons.usb,
                        title: 'Sync USB (HP ⇄ Laptop)',
                        selected: false,
                        onTap: _showUsbSyncDialog,
                      ),
                      _sidebarTile(
                        icon: Icons.download_for_offline_outlined,
                        title: 'Export Excel/CSV',
                        selected: false,
                        onTap: _exportExcelCsv,
                      ),
                      _sidebarTile(
                        icon: Icons.sync,
                        title: 'Sync & API Key',
                        selected: false,
                        onTap: _showApiSettingsModal,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (forceFull) {
      return sidebarContent;
    }
    return SizedBox(width: 240, child: sidebarContent);
  }

  Widget _sidebarTile({
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF272727) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomDate({VoidCallback? onApplied}) async {
    _dayFocusNode.unfocus();
    final res = await showDialog<(DateTime, DateTime?)>(
      context: context,
      builder: (_) =>
          _CustomCalendarDialog(isRange: false, initialDate: customDate),
    );
    if (res == null || !mounted) return;
    _applyPeriodChoice('custom_date', newCustomDate: res.$1);
    onApplied?.call();
    await _saveUiPreferences();
    await _fetchVideos();
  }

  Future<void> _pickCustomDateRange({VoidCallback? onApplied}) async {
    _dayFocusNode.unfocus();
    final res = await showDialog<(DateTime, DateTime?)>(
      context: context,
      builder: (_) => _CustomCalendarDialog(
        isRange: true,
        initialRangeStart: customRangeStart,
        initialRangeEnd: customRangeEnd,
      ),
    );
    if (res == null || res.$2 == null || !mounted) return;
    _applyPeriodChoice(
      'custom_range',
      newRangeStart: res.$1,
      newRangeEnd: res.$2,
    );
    onApplied?.call();
    await _saveUiPreferences();
    await _fetchVideos();
  }

  void _showMobileFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 720),
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        var pendingOverlap = false;
        void commitDayInput({
          bool unfocus = false,
          StateSetter? setModalState,
        }) {
          _dayInputDebounce?.cancel();
          if (unfocus && _dayFocusNode.hasFocus) {
            _dayFocusNode.unfocus();
          }
          final trimmed = _dayInputCtrl.text.trim();
          final parsed = int.tryParse(trimmed);
          final currentlyDay = _isCustomDayPeriod(period);
          if (parsed != null && parsed >= 1) {
            final nextPeriod = '${parsed}d';
            if (period != nextPeriod) {
              _applyPeriodChoice(nextPeriod);
              if (ctx.mounted) setModalState?.call(() {});
              _saveUiPreferences();
              _fetchVideos();
            }
          } else if (currentlyDay &&
              (trimmed.isEmpty || (parsed != null && parsed <= 0))) {
            _applyPeriodChoice('all');
            if (ctx.mounted) setModalState?.call(() {});
            _saveUiPreferences();
            _fetchVideos();
          }
        }

        final sheetContent = StatefulBuilder(
          builder: (modalCtx, setModalState) {
            _refreshFilterModal = () {
              if (modalCtx.mounted) setModalState(() {});
            };
            if (_activeDayFocusListener != null) {
              _dayFocusNode.removeListener(_activeDayFocusListener!);
            }
            _activeDayFocusListener = () {
              if (!modalCtx.mounted) return;
              if (_dayFocusNode.hasFocus) {
                setModalState(() {});
              } else {
                commitDayInput(setModalState: setModalState);
                if (modalCtx.mounted) setModalState(() {});
              }
            };
            _dayFocusNode.addListener(_activeDayFocusListener!);

            final periods = [
              ('all', 'All Time'),
              ('today', 'Today'),
              ('week', 'This Week'),
              ('month', 'This Month'),
              ('year', 'This Year'),
            ];
            final isCustomDay = _isCustomDayPeriod(period);
            final sorts = [
              ('views', '🔥 View Terbanyak'),
              ('likes', '👍 Like Terbanyak'),
              ('time', '🕒 Terbaru ke Terlama'),
              ('oldest', '⏳ Terlama ke Terbaru'),
            ];

            Widget hideChoice(String value, String label) {
              final active = hideFilter == value;
              return ChoiceChip(
                label: SizedBox(
                  width: double.infinity,
                  child: Text(label, textAlign: TextAlign.center),
                ),
                selected: active,
                selectedColor: value == 'hide'
                    ? const Color(0xFFFFD600)
                    : Colors.white,
                backgroundColor: const Color(0xFF2C2C2C),
                labelStyle: TextStyle(
                  color: active ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
                onSelected: (_) {
                  setState(() {
                    hideFilter = value;
                    if (selectedChannelId.isNotEmpty) {
                      final isHid = _isChannelHidden(selectedChannelId);
                      if (!_matchesHideFilter(isHid)) {
                        selectedChannelId = '';
                      }
                    }
                    currentPage = 1;
                  });
                  setModalState(() {});
                  _saveUiPreferences();
                  _fetchVideos();
                },
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Filter & Urutan Video',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF333333)),
                  const SizedBox(height: 6),
                  const Text(
                    'Urutkan:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: sorts.map((s) {
                      final active = sortBy == s.$1;
                      return ChoiceChip(
                        label: Text(s.$2),
                        selected: active,
                        selectedColor: Colors.white,
                        backgroundColor: const Color(0xFF2C2C2C),
                        labelStyle: TextStyle(
                          color: active ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                        onSelected: (_) {
                          setState(() {
                            sortBy = s.$1;
                            currentPage = 1;
                          });
                          setModalState(() {});
                          _saveUiPreferences();
                          _fetchVideos();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Channel Hide / Normal:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: hideChoice('both', 'All')),
                          const SizedBox(width: 8),
                          Expanded(child: hideChoice('unhide', 'Unhide')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: hideChoice('hide', 'Hide')),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Periode Upload:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...periods.map((p) {
                        final active = period == p.$1;
                        return SizedBox(
                          height: 36,
                          child: ChoiceChip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            side: BorderSide(
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF444444),
                              width: 1.0,
                            ),
                            label: Text(p.$2),
                            selected: active,
                            selectedColor: Colors.white,
                            backgroundColor: const Color(0xFF2C2C2C),
                            labelStyle: TextStyle(
                              color: active ? Colors.black : Colors.white,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12.5,
                            ),
                            onSelected: (_) {
                              _applyPeriodChoice(p.$1);
                              setModalState(() {});
                              _saveUiPreferences();
                              _fetchVideos();
                            },
                          ),
                        );
                      }),
                      SizedBox(
                        height: 36,
                        child: ChoiceChip(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(
                            color: period == 'custom_date'
                                ? Colors.white
                                : const Color(0xFF444444),
                            width: 1.0,
                          ),
                          avatar: Icon(
                            Icons.event,
                            size: 15,
                            color: period == 'custom_date'
                                ? Colors.black
                                : Colors.greenAccent,
                          ),
                          label: Text(
                            period == 'custom_date' && customDate != null
                                ? 'Custom Date (≤ ${_formatDateId(customDate!)})'
                                : 'Custom Date',
                          ),
                          selected: period == 'custom_date',
                          selectedColor: Colors.white,
                          backgroundColor: const Color(0xFF2C2C2C),
                          labelStyle: TextStyle(
                            color: period == 'custom_date'
                                ? Colors.black
                                : Colors.white,
                            fontWeight: period == 'custom_date'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12.5,
                          ),
                          onSelected: (_) {
                            _pickCustomDate(
                              onApplied: () {
                                if (ctx.mounted) setModalState(() {});
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        height: 36,
                        child: ChoiceChip(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(
                            color: period == 'custom_range'
                                ? Colors.white
                                : const Color(0xFF444444),
                            width: 1.0,
                          ),
                          avatar: Icon(
                            Icons.date_range,
                            size: 15,
                            color: period == 'custom_range'
                                ? Colors.black
                                : Colors.lightBlueAccent,
                          ),
                          label: Text(
                            period == 'custom_range' &&
                                    customRangeStart != null &&
                                    customRangeEnd != null
                                ? 'Custom Date Range (${_formatDateId(customRangeStart!)} – ${_formatDateId(customRangeEnd!)})'
                                : 'Custom Date Range',
                          ),
                          selected: period == 'custom_range',
                          selectedColor: Colors.white,
                          backgroundColor: const Color(0xFF2C2C2C),
                          labelStyle: TextStyle(
                            color: period == 'custom_range'
                                ? Colors.black
                                : Colors.white,
                            fontWeight: period == 'custom_range'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12.5,
                          ),
                          onSelected: (_) {
                            _pickCustomDateRange(
                              onApplied: () {
                                if (ctx.mounted) setModalState(() {});
                              },
                            );
                          },
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _dayFocusNode.requestFocus(),
                        child: Container(
                          key: const Key('hari_lalu_box'),
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isCustomDay
                                ? Colors.white
                                : const Color(0xFF2C2C2C),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCustomDay
                                  ? Colors.white
                                  : const Color(0xFF444444),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: isCustomDay ? 19 : 0,
                                child: isCustomDay
                                    ? const Padding(
                                        padding: EdgeInsets.only(right: 3),
                                        child: Icon(
                                          Icons.check,
                                          size: 15,
                                          color: Colors.black,
                                        ),
                                      )
                                    : null,
                              ),
                              SizedBox(
                                key: _dayInputSlotKey,
                                width: 44,
                                child: TextField(
                                  key: const Key('hari_lalu_input'),
                                  controller: _dayInputCtrl,
                                  focusNode: _dayFocusNode,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  scrollPadding: const EdgeInsets.only(
                                    bottom: 64,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: isCustomDay
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '2, 3..',
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: isCustomDay
                                          ? Colors.black45
                                          : Colors.white54,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    _dayInputDebounce?.cancel();
                                    final trimmed = val.trim();
                                    final parsed = int.tryParse(trimmed);
                                    if (parsed != null && parsed >= 1) {
                                      final nextPeriod = '${parsed}d';
                                      if (period != nextPeriod) {
                                        _applyPeriodChoice(nextPeriod);
                                        if (modalCtx.mounted) {
                                          setModalState(() {});
                                        }
                                        _dayInputDebounce = Timer(
                                          const Duration(milliseconds: 180),
                                          () {
                                            if (!mounted) return;
                                            _saveUiPreferences();
                                            _fetchVideos();
                                          },
                                        );
                                      }
                                    } else if (modalCtx.mounted) {
                                      setModalState(() {});
                                    }
                                  },
                                  onSubmitted: (_) => commitDayInput(
                                    unfocus: true,
                                    setModalState: setModalState,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Day',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isCustomDay
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isCustomDay
                                      ? Colors.black
                                      : Colors.white70,
                                ),
                              ),
                              if (isCustomDay ||
                                  _dayInputCtrl.text.isNotEmpty) ...[
                                const SizedBox(width: 3),
                                InkWell(
                                  key: const Key('hari_lalu_clear'),
                                  canRequestFocus: false,
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    _dayInputDebounce?.cancel();
                                    if (_dayFocusNode.hasFocus &&
                                        _dayInputCtrl.text.isNotEmpty) {
                                      _dayInputCtrl.clear();
                                      setModalState(() {});
                                    } else {
                                      _applyPeriodChoice('all');
                                      setModalState(() {});
                                      _saveUiPreferences();
                                      _fetchVideos();
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: isCustomDay
                                          ? Colors.black54
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tampil per Tab (Default 50):',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [25, 50, 100].map((val) {
                      final active = limit == val;
                      return ChoiceChip(
                        label: Text('$val Video'),
                        selected: active,
                        selectedColor: const Color(0xFFFF0033),
                        backgroundColor: const Color(0xFF2C2C2C),
                        labelStyle: TextStyle(
                          color: Colors.white,
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12.5,
                        ),
                        onSelected: (_) {
                          setState(() {
                            limit = val;
                            currentPage = 1;
                          });
                          setModalState(() {});
                          _saveUiPreferences(newLimit: val);
                          _fetchVideos();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Filter Durasi Video:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '${_formatMinutesLabel(durationRange.start.round())} – ${_formatMinutesLabel(durationRange.end.round(), isMax: true)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LayoutBuilder(
                      builder: (sliderContext, constraints) {
                        const trackInset = 16.0;
                        final trackWidth =
                            (constraints.maxWidth - trackInset * 2)
                                .clamp(1.0, double.infinity)
                                .toDouble();

                        void finishDurationDrag() {
                          pendingOverlap = false;
                          if (_activeDurationThumb == null) return;
                          setModalState(() => _activeDurationThumb = null);
                          setState(() => currentPage = 1);
                          _saveUiPreferences();
                          _fetchVideos();
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (details) {
                            pendingOverlap = false;
                            final x = details.localPosition.dx;
                            final startX =
                                trackInset +
                                durationRange.start / 120 * trackWidth;
                            final endX =
                                trackInset +
                                durationRange.end / 120 * trackWidth;
                            final startDistance = (x - startX).abs();
                            final endDistance = (x - endX).abs();
                            // Make the touch target much larger than the
                            // visible thumb, which is difficult to grab on
                            // a phone. Track presses still do not move it.
                            const thumbHitRadius = 36.0;

                            if (startDistance <= thumbHitRadius ||
                                endDistance <= thumbHitRadius) {
                              if ((durationRange.start - durationRange.end)
                                      .abs() <
                                  0.01) {
                                pendingOverlap = true;
                                setModalState(
                                  () => _activeDurationThumb = Thumb.end,
                                );
                              } else {
                                setModalState(
                                  () => _activeDurationThumb =
                                      startDistance <= endDistance
                                      ? Thumb.start
                                      : Thumb.end,
                                );
                              }
                            } else {
                              setModalState(() => _activeDurationThumb = null);
                            }
                          },
                          onHorizontalDragUpdate: (details) {
                            final rawDelta = details.primaryDelta ?? 0;
                            if (pendingOverlap && rawDelta != 0) {
                              pendingOverlap = false;
                              final picked = rawDelta > 0
                                  ? Thumb.end
                                  : Thumb.start;
                              if (_activeDurationThumb != picked) {
                                setModalState(
                                  () => _activeDurationThumb = picked,
                                );
                              }
                            }
                            final deltaMinutes = rawDelta / trackWidth * 120;
                            final thumb = _activeDurationThumb;
                            if (thumb == Thumb.start) {
                              final start = (durationRange.start + deltaMinutes)
                                  .clamp(0.0, durationRange.end)
                                  .toDouble();
                              setModalState(() {
                                durationRange = RangeValues(
                                  start,
                                  durationRange.end,
                                );
                              });
                            } else if (thumb == Thumb.end) {
                              final end = (durationRange.end + deltaMinutes)
                                  .clamp(durationRange.start, 120.0)
                                  .toDouble();
                              setModalState(() {
                                durationRange = RangeValues(
                                  durationRange.start,
                                  end,
                                );
                              });
                            }
                          },
                          onHorizontalDragEnd: (_) => finishDurationDrag(),
                          onHorizontalDragCancel: finishDurationDrag,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              IgnorePointer(
                                child: RangeSlider(
                                  values: durationRange,
                                  min: 0,
                                  max: 120,
                                  divisions: 120,
                                  activeColor: const Color(0xFFFF0033),
                                  inactiveColor: const Color(0xFF444444),
                                  onChanged: (_) {},
                                ),
                              ),
                              for (final thumb in [Thumb.start, Thumb.end])
                                Positioned(
                                  left:
                                      trackInset +
                                      (thumb == Thumb.start
                                              ? durationRange.start
                                              : durationRange.end) /
                                          120 *
                                          trackWidth -
                                      11,
                                  child: IgnorePointer(
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFFFF0033),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: _activeDurationThumb == thumb
                                              ? 2.5
                                              : 1.5,
                                        ),
                                        boxShadow: [
                                          if (_activeDurationThumb == thumb)
                                            BoxShadow(
                                              color: const Color(
                                                0xFFFF0033,
                                              ).withValues(alpha: 0.55),
                                              blurRadius: 14,
                                              spreadRadius: 4,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF0033),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        commitDayInput(unfocus: true);
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        'Terapkan (Total $totalVideos Video)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        return Builder(
          builder: (kbCtx) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(kbCtx).bottom,
              ),
              child: sheetContent,
            ),
          ),
        );
      },
    ).whenComplete(() {
      _refreshFilterModal = null;
      _dayInputDebounce?.cancel();
      if (_activeDayFocusListener != null) {
        _dayFocusNode.removeListener(_activeDayFocusListener!);
        _activeDayFocusListener = null;
      }
    });
  }

  Widget _buildFilterSortButton({double height = 38, bool compact = false}) {
    return Tooltip(
      message: 'Filter & Urutkan',
      child: SizedBox(
        height: height,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF222222),
            foregroundColor: Colors.amberAccent,
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 11),
            minimumSize: Size(0, height),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF3A3A3A)),
            ),
          ),
          icon: Icon(
            Icons.tune,
            size: compact ? 15 : 17,
            color: Colors.amberAccent,
          ),
          label: Text(
            compact ? 'Filter' : 'Filter & Urutkan',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.amberAccent,
            ),
          ),
          onPressed: _showMobileFilterBottomSheet,
        ),
      ),
    );
  }

  Widget _buildFilterAndSearchRow({
    required double screenWidth,
    required bool isMobile,
  }) {
    final compactFilter = screenWidth < 500;
    final compactSearch = screenWidth < 430;
    final height = isMobile ? (compactFilter ? 34.0 : 36.0) : 38.0;
    final searchMaxWidth = isMobile
        ? (screenWidth * 0.42).clamp(115.0, 290.0)
        : 360.0;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterSortButton(height: height, compact: compactFilter),
          SizedBox(width: compactFilter ? 5 : 8),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: searchMaxWidth),
              child: _buildSearchInputBox(
                height: height,
                hintText: compactSearch ? 'Cari...' : 'Cari video...',
                buttonWidth: compactSearch ? 36 : 42,
                leftPad: compactSearch ? 10 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSearchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: _buildSearchInputBox(
        height: 38,
        hintText: 'Cari video...',
        focusNode: _mobileSearchFocusNode,
      ),
    );
  }

  Widget _buildFilterSummaryStrip(bool isMobile) {
    final sorts = [
      ('views', '🔥 View Terbanyak'),
      ('likes', '👍 Like Terbanyak'),
      ('time', '🕒 Terbaru ke Terlama'),
      ('oldest', '⏳ Terlama ke Terbaru'),
    ];
    final sortLabel = sorts
        .firstWhere((s) => s.$1 == sortBy, orElse: () => sorts[2])
        .$2;
    final periodLabel = _periodDisplayLabel();
    final hideLabel = hideFilter == 'both'
        ? '👁️ All'
        : (hideFilter == 'hide' ? '🟨 Hide' : '👁️ Unhide');
    final durationLabel =
        'Durasi: ${_formatMinutesLabel(durationRange.start.round())} – ${_formatMinutesLabel(durationRange.end.round(), isMax: true)}';
    final channelLabel = selectedChannelId.isEmpty
        ? null
        : channels
              .firstWhere(
                (c) => (c['channel_id'] ?? '').toString() == selectedChannelId,
                orElse: () => const <String, dynamic>{},
              )['title']
              ?.toString();
    final parts = <String>[
      if (channelLabel != null && channelLabel.isNotEmpty) channelLabel,
      if (isMobile && searchQuery.isNotEmpty) 'Cari: "$searchQuery"',
      sortLabel,
      hideLabel,
      periodLabel,
      durationLabel,
      '$limit Video/Tab',
      'Total: $totalVideos video',
    ];
    final summaryText = parts.join('  •  ');

    if (!isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Center(
          child: Text(
            summaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showMobileFilterBottomSheet,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF282828)),
          ),
          child: Text(
            summaryText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarLiveSection({bool isDrawer = false}) {
    final liveList = _visibleLiveStreams(ignoreSelectedChannel: true);
    return Container(
      key: const Key('sidebar_live_section'),
      margin: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: liveList.isNotEmpty
              ? const Color(0x55FF0033)
              : const Color(0xFF282828),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: liveList.isNotEmpty
                      ? const Color(0xFFFF0033)
                      : Colors.white38,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Live Streaming (${liveList.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (liveList.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Belum ada akun yang live',
                style: TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            for (final item in liveList)
              Builder(
                builder: (ctx) {
                  final cid = (item['channel_id'] ?? '').toString();
                  final chTitle = (item['channel_title'] ?? '').toString();
                  final chThumb = (item['channel_thumbnail'] ?? '').toString();
                  return InkWell(
                    key: Key('sidebar_live_item_$cid'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (isDrawer && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                      _openYouTubeVideo(item);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFFF0033),
                            ),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: const Color(0xFF383838),
                              backgroundImage: chThumb.isNotEmpty
                                  ? NetworkImage(chThumb)
                                  : null,
                              onBackgroundImageError: chThumb.isNotEmpty
                                  ? (_, _) {}
                                  : null,
                              child: Text(
                                chTitle.isNotEmpty ? chTitle[0] : '?',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              chTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF0033),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainLiveSection() {
    final liveList = _visibleLiveStreams();
    return Container(
      key: const Key('main_live_section'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: liveList.isEmpty ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: liveList.isNotEmpty
              ? const Color(0x66FF0033)
              : const Color(0xFF282828),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: liveList.isNotEmpty
                      ? const Color(0xFFFF0033)
                      : Colors.white38,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Live Streaming (${liveList.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (liveList.isEmpty) ...[
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Belum ada yang sedang live',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
              ],
            ],
          ),
          if (liveList.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: liveList.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, idx) {
                  final item = liveList[idx];
                  final cid = (item['channel_id'] ?? '').toString();
                  final chTitle = (item['channel_title'] ?? '').toString();
                  final streamTitle = (item['title'] ?? '').toString();
                  final chThumb = (item['channel_thumbnail'] ?? '').toString();
                  return InkWell(
                    key: Key('main_live_item_$cid'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openYouTubeVideo(item),
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF212121),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x55FF0033)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFFF0033),
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF383838),
                              backgroundImage: chThumb.isNotEmpty
                                  ? NetworkImage(chThumb)
                                  : null,
                              onBackgroundImageError: chThumb.isNotEmpty
                                  ? (_, _) {}
                                  : null,
                              child: Text(
                                chTitle.isNotEmpty ? chTitle[0] : '?',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        chTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF0033),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'LIVE',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (streamTitle.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    streamTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaginationTabsBar() {
    if (totalVideos <= 0) {
      return const SizedBox.shrink();
    }
    final safeCurrent = currentPage.clamp(1, totalPages);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Navigasi Tab:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          // Tombol Kiri (Sebelumnya)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF272727),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: safeCurrent > 1
                ? () {
                    setState(() => currentPage = safeCurrent - 1);
                    _fetchVideos();
                  }
                : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Sebelumnya'),
          ),
          // Tombol Daftar Tab Halaman (Dialog + Interactive Fast Scrollbar)
          Builder(
            builder: (ctx) {
              final startItem = (safeCurrent - 1) * limit + 1;
              final endItem = (safeCurrent * limit > totalVideos)
                  ? totalVideos
                  : safeCurrent * limit;
              return InkWell(
                key: const Key('tab_selector_btn'),
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final selected = await showDialog<int>(
                    context: ctx,
                    builder: (_) => TabPickerDialog(
                      totalPages: totalPages,
                      limit: limit,
                      totalVideos: totalVideos,
                      currentPage: safeCurrent,
                    ),
                  );
                  if (selected != null && selected != currentPage) {
                    setState(() => currentPage = selected);
                    _fetchVideos();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212121),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF0033)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tab $safeCurrent ($startItem–$endItem)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              );
            },
          ),
          // Tombol Kanan (Berikutnya)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF272727),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: safeCurrent < totalPages
                ? () {
                    setState(() => currentPage = safeCurrent + 1);
                    _fetchVideos();
                  }
                : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Berikutnya'),
          ),
          Text(
            'Halaman $safeCurrent dari $totalPages ($totalVideos video)',
            style: const TextStyle(fontSize: 12.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoGridWithPagination(double screenWidth) {
    final isMobile = MediaQuery.of(context).size.width < 750;
    if (videos.isEmpty) {
      return Column(
        children: [
          if (isMobile && _showMobileSearch) _buildMobileSearchRow(),
          _buildFilterSummaryStrip(isMobile),
          _buildMainLiveSection(),
          const Expanded(
            child: Center(
              child: Text(
                'Tidak ada video pada filter waktu / pencarian ini.',
                style: TextStyle(color: Colors.white60, fontSize: 15),
              ),
            ),
          ),
        ],
      );
    }

    int crossAxisCount = 3;
    if (screenWidth < 650) {
      crossAxisCount = 1;
    } else if (screenWidth < 1000) {
      crossAxisCount = 2;
    }

    final scrollView = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CustomScrollView(
        controller: _videoScrollController,
        slivers: [
          if (isMobile && _showMobileSearch)
            SliverToBoxAdapter(child: _buildMobileSearchRow()),
          SliverToBoxAdapter(child: _buildFilterSummaryStrip(isMobile)),
          SliverToBoxAdapter(child: _buildPaginationTabsBar()),
          SliverToBoxAdapter(child: _buildMainLiveSection()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 22,
                childAspectRatio: 1.12,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final v = videos[index];
                return _buildVideoCard(v);
              }, childCount: videos.length),
            ),
          ),
          SliverToBoxAdapter(child: _buildPaginationTabsBar()),
          const SliverToBoxAdapter(child: SizedBox(height: 72)),
        ],
      ),
    );

    return _HomeScrollWithBar(
      controller: _videoScrollController,
      itemCount: videos.length,
      scrollView: scrollView,
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> v) {
    final title = (v['title'] ?? '').toString();
    final channelId = (v['channel_id'] ?? '').toString();
    final channelTitle = (v['channel_title'] ?? '').toString();
    final thumbUrl = (v['thumbnail_url'] ?? '').toString();
    final channelThumb = (v['channel_thumbnail'] ?? '').toString();
    final views = int.tryParse((v['view_count'] ?? 0).toString()) ?? 0;
    final likes = int.tryParse((v['like_count'] ?? 0).toString()) ?? 0;
    final publishedAt = (v['published_at'] ?? '').toString();
    final duration = (v['duration'] ?? '').toString();
    final vHp = int.tryParse((v['views_hp'] ?? 0).toString()) ?? 0;
    final vLap = int.tryParse((v['views_laptop'] ?? 0).toString()) ?? 0;
    final vTot =
        int.tryParse((v['views_total'] ?? 0).toString()) ?? (vHp + vLap);
    final creatorWatched = _getCreatorWatchedCount(channelId, v);
    final watchedCount = vTot > 0 ? vTot : creatorWatched;
    final isChannelHidden = _isChannelHidden(channelId, v);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openYouTubeVideo(v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFF272727),
                      child: const Center(
                        child: Icon(
                          Icons.ondemand_video,
                          size: 42,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isLiveFlag(v['is_live']))
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0033),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  )
                else if (duration.isNotEmpty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        duration,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF383838),
                backgroundImage: channelThumb.isNotEmpty
                    ? NetworkImage(channelThumb)
                    : null,
                onBackgroundImageError: channelThumb.isNotEmpty
                    ? (_, _) {}
                    : null,
                child: Text(
                  channelTitle.isNotEmpty ? channelTitle[0] : '?',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            channelTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFAAAAAA),
                            ),
                          ),
                        ),
                        if (isChannelHidden) ...[
                          const SizedBox(width: 6),
                          _buildHiddenBadge(key: Key('card_hidden_$channelId')),
                        ],
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_circle,
                          size: 13,
                          color: Color(0xFFAAAAAA),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_formatCompactNumber(views)} views',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                        const Text(
                          '•',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                        Text(
                          _formatTimeAgo(publishedAt),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                        const Text(
                          '•',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF272727),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '👍 ${_formatCompactNumber(likes)} likes',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Tooltip(
                          message:
                              'Total: $watchedCount view\n📱 HP: $vHp view | 💻 Laptop: $vLap view',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: watchedCount > 0
                                  ? const Color(0xFF1E3A2F)
                                  : const Color(0xFF272727),
                              borderRadius: BorderRadius.circular(4),
                              border: watchedCount > 0
                                  ? Border.all(
                                      color: const Color(0xFF2E7D32),
                                      width: 0.8,
                                    )
                                  : null,
                            ),
                            child: Text(
                              '▶ $watchedCount view',
                              style: TextStyle(
                                fontSize: 12,
                                color: watchedCount > 0
                                    ? const Color(0xFF81C784)
                                    : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Titik 3 (⋮) di pojok kanan bawah kartu video: Unsubscribe, Tonton di YouTube, Transkrip, Unhide/Hide
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: Colors.white70,
                ),
                color: const Color(0xFF282828),
                tooltip: 'Opsi Creator',
                onSelected: (value) {
                  if (value == 'open_yt') {
                    _openYouTubeVideo(v);
                  } else if (value == 'transcript') {
                    _showTranscriptPromptDialog(v);
                  }
                },
                itemBuilder: (popupCtx) => [
                  PopupMenuItem<String>(
                    enabled:
                        false, // Agar klik biasa tidak langsung menutup menu; harus ditahan 1 detik
                    padding: EdgeInsets.zero,
                    child: _HoldToActionMenuItem(
                      label: 'Unsubscribe "$channelTitle"',
                      idleSubtitle:
                          (skipUnsubscribeConfirmUntil != null &&
                              DateTime.now().isBefore(
                                skipUnsubscribeConfirmUntil!,
                              ))
                          ? '⚡ Tahan 1 detik untuk langsung Unsubscribe'
                          : '👆 Tahan 1 detik untuk Unsubscribe',
                      icon: Icons.person_remove,
                      accentColor: const Color(0xFFFF4E4E),
                      labelColor: const Color(0xFFFF6B6B),
                      activeBgColor: const Color(0xFF4A1818),
                      progressBarColor: const Color(0xFFFF0033),
                      onHoldCompleted: () {
                        Navigator.of(popupCtx).pop();
                        _confirmOrUnsubscribeChannel(channelId, channelTitle);
                      },
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'open_yt',
                    child: Row(
                      children: [
                        Icon(
                          Icons.open_in_new,
                          color: Colors.white70,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tonton di YouTube',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'transcript',
                    child: Row(
                      children: [
                        Icon(
                          Icons.subtitles_outlined,
                          color: Colors.white70,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Transkrip',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    enabled: false,
                    padding: EdgeInsets.zero,
                    child: _HoldToActionMenuItem(
                      label: isChannelHidden
                          ? 'Unhide "$channelTitle"'
                          : 'Hide "$channelTitle"',
                      idleSubtitle: isChannelHidden
                          ? '👆 Tahan 1 detik untuk Unhide'
                          : '👆 Tahan 1 detik untuk Hide',
                      icon: isChannelHidden
                          ? Icons.visibility
                          : Icons.visibility_off,
                      accentColor: const Color(0xFFFFD600),
                      labelColor: const Color(0xFFFFE57F),
                      activeBgColor: const Color(0xFF42360A),
                      progressBarColor: const Color(0xFFFFD600),
                      onHoldCompleted: () {
                        Navigator.of(popupCtx).pop();
                        _toggleChannelHidden(
                          channelId,
                          channelTitle,
                          hide: !isChannelHidden,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoldToActionMenuItem extends StatefulWidget {
  final String label;
  final String idleSubtitle;
  final IconData icon;
  final Color accentColor;
  final Color labelColor;
  final Color activeBgColor;
  final Color progressBarColor;
  final VoidCallback onHoldCompleted;

  const _HoldToActionMenuItem({
    required this.label,
    required this.idleSubtitle,
    required this.icon,
    required this.accentColor,
    required this.labelColor,
    required this.activeBgColor,
    required this.progressBarColor,
    required this.onHoldCompleted,
  });

  @override
  State<_HoldToActionMenuItem> createState() => _HoldToActionMenuItemState();
}

class _HoldToActionMenuItemState extends State<_HoldToActionMenuItem> {
  Timer? _holdTimer;
  double _holdProgress = 0.0; // 0.0 .. 1.0 (1 detik)
  bool _holding = false;

  void _startHolding() {
    _holdTimer?.cancel();
    setState(() {
      _holding = true;
      _holdProgress = 0.05;
    });
    const stepMs = 50;
    const totalMs = 1000; // Tahan 1 detik
    _holdTimer = Timer.periodic(const Duration(milliseconds: stepMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = _holdProgress + (stepMs / totalMs);
      if (next >= 1.0) {
        timer.cancel();
        setState(() {
          _holdProgress = 1.0;
          _holding = false;
        });
        widget.onHoldCompleted();
      } else {
        setState(() {
          _holdProgress = next;
        });
      }
    });
  }

  void _cancelHolding() {
    _holdTimer?.cancel();
    if (mounted && _holdProgress < 1.0) {
      setState(() {
        _holding = false;
        _holdProgress = 0.0;
      });
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_holdProgress * 100).round();
    return Listener(
      onPointerDown: (_) => _startHolding(),
      onPointerUp: (_) => _cancelHolding(),
      onPointerCancel: (_) => _cancelHolding(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _holding ? widget.activeBgColor : Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _holding
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _holdProgress,
                                strokeWidth: 2.2,
                                color: widget.accentColor,
                                backgroundColor: Colors.white24,
                              ),
                              Text(
                                '$pct%',
                                style: const TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Icon(widget.icon, color: widget.accentColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.labelColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _holding ? 'Tahan terus... ($pct%)' : widget.idleSubtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: _holding ? Colors.amberAccent : Colors.white54,
                ),
              ),
              if (_holding) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _holdProgress,
                    minHeight: 4,
                    color: widget.progressBarColor,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomCalendarDialog extends StatefulWidget {
  final bool isRange;
  final DateTime? initialDate;
  final DateTime? initialRangeStart;
  final DateTime? initialRangeEnd;

  const _CustomCalendarDialog({
    required this.isRange,
    this.initialDate,
    this.initialRangeStart,
    this.initialRangeEnd,
  });

  @override
  State<_CustomCalendarDialog> createState() => _CustomCalendarDialogState();
}

class _CustomCalendarDialogState extends State<_CustomCalendarDialog> {
  static const int _minYear = 1995;
  static const List<String> _monthsFull = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  static const List<String> _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  static const List<String> _dayHeaders = [
    'Min',
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
  ];

  late DateTime _today;
  late int _viewYear;
  late int _viewMonth;
  DateTime? _singleDate;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _editingEndDate = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    if (widget.isRange) {
      _rangeStart = _clampToToday(widget.initialRangeStart);
      _rangeEnd = _clampToToday(widget.initialRangeEnd);
      if (_rangeStart != null &&
          _rangeEnd != null &&
          _rangeStart!.isAfter(_rangeEnd!)) {
        final tmp = _rangeStart;
        _rangeStart = _rangeEnd;
        _rangeEnd = tmp;
      }
      _editingEndDate = _rangeStart != null && _rangeEnd == null;
      final anchor = _rangeEnd ?? _rangeStart ?? _today;
      _viewYear = anchor.year.clamp(_minYear, _today.year);
      _viewMonth = anchor.month;
    } else {
      _singleDate = _clampToToday(widget.initialDate) ?? _today;
      _viewYear = _singleDate!.year.clamp(_minYear, _today.year);
      _viewMonth = _singleDate!.month;
    }
    if (_viewYear == _today.year && _viewMonth > _today.month) {
      _viewMonth = _today.month;
    }
  }

  DateTime? _clampToToday(DateTime? d) {
    if (d == null) return null;
    final clean = DateTime(d.year, d.month, d.day);
    return clean.isAfter(_today) ? _today : clean;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtId(DateTime? d) {
    if (d == null) return 'Belum dipilih';
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd ${_monthsShort[d.month - 1]} ${d.year}';
  }

  bool get _canGoPrevMonth => !(_viewYear <= _minYear && _viewMonth <= 1);

  bool get _canGoNextMonth =>
      !(_viewYear > _today.year ||
          (_viewYear == _today.year && _viewMonth >= _today.month));

  void _changeMonth(int delta) {
    var m = _viewMonth + delta;
    var y = _viewYear;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    if (y < _minYear ||
        y > _today.year ||
        (y == _today.year && m > _today.month)) {
      return;
    }
    setState(() {
      _viewYear = y;
      _viewMonth = m;
    });
  }

  void _focusRangeEndpoint(bool isEnd) {
    setState(() {
      _editingEndDate = isEnd;
      final target = isEnd ? _rangeEnd : _rangeStart;
      if (target != null) {
        _viewYear = target.year.clamp(_minYear, _today.year);
        _viewMonth = target.month;
        if (_viewYear == _today.year && _viewMonth > _today.month) {
          _viewMonth = _today.month;
        }
      }
    });
  }

  Widget _buildRangeSelectorBox({
    required Key boxKey,
    required String title,
    required DateTime? date,
    required bool isActive,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        key: boxKey,
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? accentColor.withValues(alpha: 0.14)
                : const Color(0xFF282828),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? accentColor
                  : (date != null
                        ? const Color(0xFF5A5A5A)
                        : const Color(0xFF3E3E3E)),
              width: isActive ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive ? accentColor : Colors.white54,
                      ),
                    ),
                  ),
                  if (isActive) Icon(Icons.edit, size: 12, color: accentColor),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _fmtId(date),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapDay(DateTime cellDate) {
    if (cellDate.isAfter(_today)) return;
    setState(() {
      if (!widget.isRange) {
        _singleDate = cellDate;
      } else if (!_editingEndDate) {
        _rangeStart = cellDate;
        if (_rangeEnd == null) {
          _editingEndDate = true;
        } else if (_rangeStart!.isAfter(_rangeEnd!)) {
          final tmp = _rangeStart;
          _rangeStart = _rangeEnd;
          _rangeEnd = tmp;
        }
      } else {
        _rangeEnd = cellDate;
        if (_rangeStart == null) {
          _editingEndDate = false;
        } else if (_rangeEnd!.isBefore(_rangeStart!)) {
          final tmp = _rangeStart;
          _rangeStart = _rangeEnd;
          _rangeEnd = tmp;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_viewYear, _viewMonth, 1);
    final leadingBlanks =
        firstOfMonth.weekday % 7; // Sunday = 0 .. Saturday = 6
    final daysInMonth = DateUtils.getDaysInMonth(_viewYear, _viewMonth);
    final totalCells = leadingBlanks + daysInMonth;
    final rowCount = ((totalCells + 6) ~/ 7);
    final maxMonthForYear = _viewYear == _today.year ? _today.month : 12;
    final canApply = widget.isRange
        ? (_rangeStart != null && _rangeEnd != null)
        : (_singleDate != null);

    return AlertDialog(
      backgroundColor: const Color(0xFF1F1F1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      title: Row(
        children: [
          Icon(
            widget.isRange ? Icons.date_range : Icons.event,
            color: widget.isRange ? Colors.lightBlueAccent : Colors.greenAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isRange ? 'Custom Date Range' : 'Custom Date',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (widget.isRange && (_rangeStart != null || _rangeEnd != null))
            TextButton(
              onPressed: () => setState(() {
                _rangeStart = null;
                _rangeEnd = null;
                _editingEndDate = false;
              }),
              child: const Text(
                'Reset',
                style: TextStyle(fontSize: 12, color: Colors.amberAccent),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isRange
                    ? 'Ketuk kotak Start Date atau End Date kapan saja untuk memilih atau merevisi tanggal.'
                    : 'Pilih satu tanggal sebagai batas akhir upload video (≤ tanggal dipilih).',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 10),
              if (widget.isRange)
                Row(
                  children: [
                    _buildRangeSelectorBox(
                      boxKey: const Key('range_start_selector'),
                      title: 'Start Date',
                      date: _rangeStart,
                      isActive: !_editingEndDate,
                      accentColor: Colors.amberAccent,
                      onTap: () => _focusRangeEndpoint(false),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ),
                    _buildRangeSelectorBox(
                      boxKey: const Key('range_end_selector'),
                      title: 'End Date',
                      date: _rangeEnd,
                      isActive: _editingEndDate,
                      accentColor: Colors.lightBlueAccent,
                      onTap: () => _focusRangeEndpoint(true),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Batas Waktu Dipilih:',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmtId(_singleDate),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              // Month & Year navigation bar (supports fast cross-month & cross-year jumps)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    tooltip: 'Bulan Sebelumnya',
                    onPressed: _canGoPrevMonth ? () => _changeMonth(-1) : null,
                  ),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('calendar_month_dropdown'),
                        value: _viewMonth,
                        isExpanded: true,
                        menuMaxHeight: 280,
                        dropdownColor: const Color(0xFF282828),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        items: [
                          for (int m = 1; m <= maxMonthForYear; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(_monthsFull[m - 1]),
                            ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _viewMonth = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('calendar_year_dropdown'),
                        value: _viewYear,
                        isExpanded: true,
                        menuMaxHeight: 280,
                        dropdownColor: const Color(0xFF282828),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        items: [
                          for (int y = _today.year; y >= _minYear; y--)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _viewYear = val;
                            if (_viewYear == _today.year &&
                                _viewMonth > _today.month) {
                              _viewMonth = _today.month;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: _canGoNextMonth ? Colors.white : Colors.white24,
                    ),
                    tooltip: 'Bulan Berikutnya',
                    onPressed: _canGoNextMonth ? () => _changeMonth(1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Day-of-week header
              Row(
                children: _dayHeaders
                    .map(
                      (h) => Expanded(
                        child: Center(
                          child: Text(
                            h,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 4),
              // Day cells
              Column(
                children: List.generate(rowCount, (row) {
                  return Row(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      final dayNum = idx - leadingBlanks + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const Expanded(child: SizedBox(height: 36));
                      }
                      final cellDate = DateTime(_viewYear, _viewMonth, dayNum);
                      final isToday = _sameDay(cellDate, _today);
                      final isFuture = cellDate.isAfter(_today);
                      final isSelectedSingle =
                          !widget.isRange &&
                          _singleDate != null &&
                          _sameDay(cellDate, _singleDate!);
                      final isStart =
                          widget.isRange &&
                          _rangeStart != null &&
                          _sameDay(cellDate, _rangeStart!);
                      final isEnd =
                          widget.isRange &&
                          _rangeEnd != null &&
                          _sameDay(cellDate, _rangeEnd!);
                      final isInRange =
                          widget.isRange &&
                          _rangeStart != null &&
                          _rangeEnd != null &&
                          cellDate.isAfter(_rangeStart!) &&
                          cellDate.isBefore(_rangeEnd!);
                      final isEndpoint = isSelectedSingle || isStart || isEnd;

                      Color bgColor = Colors.transparent;
                      BoxBorder? border;
                      Color textColor = Colors.white;
                      if (isFuture) {
                        textColor = Colors.white24;
                      } else if (isToday && !isEndpoint) {
                        bgColor = Colors.green;
                        border = Border.all(
                          color: Colors.greenAccent,
                          width: 1.5,
                        );
                        textColor = Colors.white;
                      } else if (isEndpoint) {
                        bgColor = widget.isRange
                            ? (isStart && !isEnd
                                  ? const Color(0xFFEF6C00)
                                  : const Color(0xFF1976D2))
                            : const Color(0xFFFF0033);
                        border = isToday
                            ? Border.all(color: Colors.green, width: 2.5)
                            : null;
                        textColor = Colors.white;
                      } else if (isInRange) {
                        bgColor = const Color(
                          0xFF1976D2,
                        ).withValues(alpha: 0.28);
                        textColor = Colors.white;
                      }

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: InkWell(
                            key: Key(
                              'cal_day_${cellDate.year}_${cellDate.month}_${cellDate.day}',
                            ),
                            borderRadius: BorderRadius.circular(8),
                            onTap: isFuture ? null : () => _onTapDay(cellDate),
                            child: Container(
                              height: 34,
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: border,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$dayNum',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: (isToday || isEndpoint)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
              const SizedBox(height: 10),
              // Legend
              Wrap(
                spacing: 10,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Hari Ini',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Tanggal masa depan nonaktif',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.isRange
                ? const Color(0xFF1976D2)
                : const Color(0xFFFF0033),
            foregroundColor: Colors.white,
          ),
          onPressed: canApply
              ? () {
                  if (widget.isRange) {
                    Navigator.pop(context, (_rangeStart!, _rangeEnd));
                  } else {
                    Navigator.pop(context, (_singleDate!, null));
                  }
                }
              : null,
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}

class TabPickerDialog extends StatefulWidget {
  final int totalPages;
  final int limit;
  final int totalVideos;
  final int currentPage;

  const TabPickerDialog({
    super.key,
    required this.totalPages,
    required this.limit,
    required this.totalVideos,
    required this.currentPage,
  });

  @override
  State<TabPickerDialog> createState() => _TabPickerDialogState();
}

class _TabPickerDialogState extends State<TabPickerDialog> {
  static const double _itemExtent = 46.0;
  late final ScrollController _ctrl;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final targetOffset = ((widget.currentPage - 1) * _itemExtent - 92.0).clamp(
      0.0,
      double.infinity,
    );
    _ctrl = ScrollController(initialScrollOffset: targetOffset);
    _ctrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  void _jumpToTrackY(double dy, double trackH, double thumbH) {
    if (!_ctrl.hasClients) return;
    final maxExtent = _ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final usable = (trackH - thumbH).clamp(1.0, double.infinity);
    final frac = ((dy - thumbH / 2) / usable).clamp(0.0, 1.0);
    _ctrl.jumpTo(frac * maxExtent);
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final desiredH = (widget.totalPages * _itemExtent).clamp(
      140.0,
      screenH * 0.72,
    );
    return Dialog(
      backgroundColor: const Color(0xFF212121),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF383838)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, maxHeight: screenH * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih Tab (1–${widget.totalPages})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white70,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF333333)),
            Flexible(
              child: SizedBox(
                height: desiredH,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final trackH = constraints.maxHeight;
                    final totalContentH = widget.totalPages * _itemExtent;
                    final canScroll = totalContentH > trackH + 1.0;
                    final maxExtent = canScroll
                        ? (_ctrl.hasClients &&
                                  _ctrl.position.hasContentDimensions
                              ? _ctrl.position.maxScrollExtent
                              : totalContentH - trackH)
                        : 0.0;
                    final currentOffset =
                        (_ctrl.hasClients &&
                            _ctrl.position.hasContentDimensions)
                        ? _ctrl.offset.clamp(0.0, maxExtent)
                        : 0.0;
                    final thumbH = canScroll
                        ? (trackH * (trackH / totalContentH)).clamp(
                            36.0,
                            trackH,
                          )
                        : trackH;
                    final thumbTop = (canScroll && maxExtent > 0)
                        ? (currentOffset / maxExtent) * (trackH - thumbH)
                        : 0.0;
                    final hoverTab = ((currentOffset / _itemExtent).floor() + 1)
                        .clamp(1, widget.totalPages);

                    return Row(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            controller: _ctrl,
                            itemExtent: _itemExtent,
                            itemCount: widget.totalPages,
                            itemBuilder: (_, idx) {
                              final pageNum = idx + 1;
                              final startItem = idx * widget.limit + 1;
                              final endItem =
                                  ((idx + 1) * widget.limit >
                                      widget.totalVideos)
                                  ? widget.totalVideos
                                  : (idx + 1) * widget.limit;
                              final selected = pageNum == widget.currentPage;
                              return InkWell(
                                onTap: () => Navigator.pop(context, pageNum),
                                child: Container(
                                  color: selected
                                      ? const Color(0xFF383838)
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Tab $pageNum ($startItem–$endItem)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 13.5,
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (canScroll)
                          _FastScrollbarTrack(
                            railKey: const Key('tab_fast_scrollbar'),
                            thumbKey: const Key('tab_fast_thumb'),
                            width: 28,
                            trackH: trackH,
                            thumbH: thumbH,
                            thumbTop: thumbTop,
                            dragging: _dragging,
                            dragLabel: 'Tab $hoverTab',
                            badgeRight: 36,
                            onJumpToY: (dy) =>
                                _jumpToTrackY(dy, trackH, thumbH),
                            onDragStateChanged: (v) =>
                                setState(() => _dragging = v),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FastScrollbarTrack extends StatelessWidget {
  final Key railKey;
  final Key thumbKey;
  final double width;
  final double trackH;
  final double thumbH;
  final double thumbTop;
  final bool dragging;
  final String dragLabel;
  final double badgeRight;
  final ValueChanged<double> onJumpToY;
  final ValueChanged<bool> onDragStateChanged;

  const _FastScrollbarTrack({
    required this.railKey,
    required this.thumbKey,
    required this.width,
    required this.trackH,
    required this.thumbH,
    required this.thumbTop,
    required this.dragging,
    required this.dragLabel,
    required this.badgeRight,
    required this.onJumpToY,
    required this.onDragStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          key: railKey,
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onJumpToY(d.localPosition.dy),
          onVerticalDragStart: (d) {
            onDragStateChanged(true);
            onJumpToY(d.localPosition.dy);
          },
          onVerticalDragUpdate: (d) => onJumpToY(d.localPosition.dy),
          onVerticalDragEnd: (_) => onDragStateChanged(false),
          onVerticalDragCancel: () => onDragStateChanged(false),
          child: SizedBox(
            width: width,
            height: trackH,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: 6,
                  height: trackH,
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Positioned(
                  top: thumbTop,
                  child: Container(
                    key: thumbKey,
                    width: dragging ? 12 : 9,
                    height: thumbH,
                    decoration: BoxDecoration(
                      color: dragging
                          ? const Color(0xFFFF0033)
                          : Colors.white70,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (dragging)
          Positioned(
            right: badgeRight,
            top: (thumbTop + thumbH / 2 - 14).clamp(
              4.0,
              (trackH - 32).clamp(4.0, trackH),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0033),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                dragLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeScrollWithBar extends StatefulWidget {
  final ScrollController controller;
  final int itemCount;
  final Widget scrollView;
  final Key railKey;
  final Key thumbKey;
  final String itemLabel;
  final EdgeInsets trackPadding;

  const _HomeScrollWithBar({
    required this.controller,
    required this.itemCount,
    required this.scrollView,
    this.railKey = const Key('home_fast_scrollbar'),
    this.thumbKey = const Key('home_fast_thumb'),
    this.itemLabel = 'Video',
    this.trackPadding = const EdgeInsets.only(top: 6, right: 2, bottom: 64),
  });

  @override
  State<_HomeScrollWithBar> createState() => _HomeScrollWithBarState();
}

class _HomeScrollWithBarState extends State<_HomeScrollWithBar> {
  bool _dragging = false;
  double _lastMaxExtent = -1.0;

  @override
  void initState() {
    super.initState();
    _scheduleExtentSync();
  }

  @override
  void didUpdateWidget(covariant _HomeScrollWithBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.controller != widget.controller) {
      _scheduleExtentSync();
    }
  }

  void _scheduleExtentSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller.positions.length != 1) return;
      final pos = widget.controller.position;
      if (!pos.hasContentDimensions) return;
      if ((pos.maxScrollExtent - _lastMaxExtent).abs() > 1.0) {
        _lastMaxExtent = pos.maxScrollExtent;
        setState(() {});
      }
    });
  }

  void _jumpToTrackY(double dy, double trackH, double thumbH) {
    if (widget.controller.positions.length != 1) return;
    final pos = widget.controller.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) return;
    final usable = (trackH - thumbH).clamp(1.0, double.infinity);
    final frac = ((dy - thumbH / 2) / usable).clamp(0.0, 1.0);
    widget.controller.jumpTo(frac * pos.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if ((notification.metrics.maxScrollExtent - _lastMaxExtent).abs() >
            1.0) {
          _scheduleExtentSync();
        }
        return false;
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.scrollView),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (ctx, _) {
              final hasPos =
                  widget.controller.positions.length == 1 &&
                  widget.controller.position.hasContentDimensions;
              final maxExtent = hasPos
                  ? widget.controller.position.maxScrollExtent
                  : 0.0;
              final viewportH = hasPos
                  ? widget.controller.position.viewportDimension
                  : 0.0;
              if (maxExtent <= 1.0 || viewportH <= 0.0) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: widget.trackPadding,
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final trackH = constraints.maxHeight;
                    if (trackH <= 24.0) return const SizedBox.shrink();
                    final totalContentH = maxExtent + viewportH;
                    final currentOffset = widget.controller.offset.clamp(
                      0.0,
                      maxExtent,
                    );
                    final thumbH = (trackH * (viewportH / totalContentH)).clamp(
                      36.0,
                      trackH,
                    );
                    final thumbTop = maxExtent > 0
                        ? (currentOffset / maxExtent) * (trackH - thumbH)
                        : 0.0;
                    final frac = maxExtent > 0
                        ? (currentOffset / maxExtent).clamp(0.0, 1.0)
                        : 0.0;
                    final hoverItem = widget.itemCount <= 1
                        ? widget.itemCount
                        : (frac * (widget.itemCount - 1)).round() + 1;

                    return _FastScrollbarTrack(
                      railKey: widget.railKey,
                      thumbKey: widget.thumbKey,
                      width: 24,
                      trackH: trackH,
                      thumbH: thumbH,
                      thumbTop: thumbTop,
                      dragging: _dragging,
                      dragLabel:
                          '${widget.itemLabel} $hoverItem / ${widget.itemCount}',
                      badgeRight: 32,
                      onJumpToY: (dy) => _jumpToTrackY(dy, trackH, thumbH),
                      onDragStateChanged: (v) => setState(() => _dragging = v),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DisposeOnUnmount extends StatefulWidget {
  final VoidCallback onDispose;
  final Widget child;
  const _DisposeOnUnmount({required this.onDispose, required this.child});

  @override
  State<_DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<_DisposeOnUnmount> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
