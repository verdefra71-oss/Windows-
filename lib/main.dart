import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await DatabaseHelper.instance.createAutomaticBackup();
  runApp(const PreventiviApp());
}

class PreventiviApp extends StatelessWidget {
  const PreventiviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestione Preventivi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('preventivi_full.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();

    return openDatabase(
      p.join(dbPath, fileName),
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE clienti (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL,
  email TEXT,
  telefono TEXT,
  indirizzo TEXT,
  partita_iva TEXT,
  codice_fiscale TEXT
)
''');

        await db.execute('''
CREATE TABLE prodotti (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL,
  prezzo REAL NOT NULL
)
''');

        await db.execute('''
CREATE TABLE preventivi (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  numero TEXT NOT NULL,
  data TEXT NOT NULL,
  cliente TEXT NOT NULL,
  totale REAL NOT NULL,
  numero_rate INTEGER NOT NULL,
  articoli TEXT NOT NULL DEFAULT '[]',
  iva_percent REAL NOT NULL DEFAULT 0
)
''');

        await db.execute('''
CREATE TABLE rate (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  preventivo_id INTEGER NOT NULL,
  cliente TEXT NOT NULL,
  importo REAL NOT NULL,
  data_scadenza TEXT NOT NULL,
  pagata INTEGER NOT NULL DEFAULT 0
)
''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN articoli TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN iva_percent REAL NOT NULL DEFAULT 0",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE clienti ADD COLUMN partita_iva TEXT",
          );
          await db.execute(
            "ALTER TABLE clienti ADD COLUMN codice_fiscale TEXT",
          );
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> getClienti() async {
    return (await database).query('clienti', orderBy: 'nome COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getPreventivi() async {
    return (await database).query('preventivi', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getProdotti() async {
    return (await database).query('prodotti', orderBy: 'nome COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getRate() async {
    return (await database).query('rate', orderBy: 'data_scadenza');
  }

  Future<int> insertProdotto({
    required String nome,
    required double prezzo,
  }) async {
    final id = await (await database).insert('prodotti', {
      'nome': nome,
      'prezzo': prezzo,
    });
    await autoBackup();
    return id;
  }

  Future<int> updateProdotto({
    required int id,
    required String nome,
    required double prezzo,
  }) async {
    final result = await (await database).update(
      'prodotti',
      {'nome': nome, 'prezzo': prezzo},
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<int> deleteProdotto(int id) async {
    final result = await (await database).delete(
      'prodotti',
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<int> insertCliente({
    required String nome,
    String email = '',
    String telefono = '',
    String indirizzo = '',
    String partitaIva = '',
    String codiceFiscale = '',
  }) async {
    final id = await (await database).insert('clienti', {
      'nome': nome,
      'email': email,
      'telefono': telefono,
      'indirizzo': indirizzo,
      'partita_iva': partitaIva,
      'codice_fiscale': codiceFiscale,
    });
    await autoBackup();
    return id;
  }

  Future<int> updateCliente({
    required int id,
    required String nome,
    String email = '',
    String telefono = '',
    String indirizzo = '',
    String partitaIva = '',
    String codiceFiscale = '',
  }) async {
    final result = await (await database).update(
      'clienti',
      {
        'nome': nome,
        'email': email,
        'telefono': telefono,
        'indirizzo': indirizzo,
        'partita_iva': partitaIva,
        'codice_fiscale': codiceFiscale,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<int> deleteCliente(int id) async {
    final result = await (await database).delete(
      'clienti',
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<String> prossimoNumeroPreventivo() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM preventivi');
    final n = (rows.first['n'] as int? ?? 0) + 1;
    return 'PREV-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';
  }

  Future<int> insertPreventivo({
    required String numero,
    required String cliente,
    required double totale,
    required int numeroRate,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
  }) async {
    final id = await (await database).insert('preventivi', {
      'numero': numero,
      'data': DateTime.now().toIso8601String(),
      'cliente': cliente,
      'totale': totale,
      'numero_rate': numeroRate,
      'articoli': jsonEncode(articoli),
      'iva_percent': ivaPercent,
    });
    await autoBackup();
    return id;
  }

  Future<int> updatePreventivo({
    required int id,
    required String cliente,
    required double totale,
    required int numeroRate,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
  }) async {
    final result = await (await database).update(
      'preventivi',
      {
        'cliente': cliente,
        'totale': totale,
        'numero_rate': numeroRate,
        'articoli': jsonEncode(articoli),
        'iva_percent': ivaPercent,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<void> insertRata({
    required int preventivoId,
    required String cliente,
    required double importo,
    required DateTime dataScadenza,
  }) async {
    await (await database).insert('rate', {
      'preventivo_id': preventivoId,
      'cliente': cliente,
      'importo': importo,
      'data_scadenza': dataScadenza.toIso8601String(),
      'pagata': 0,
    });
    await autoBackup();
  }



  Future<Map<String, dynamic>> _backupData() async {
    final db = await database;
    return {
      'backupVersion': 1,
      'app': 'Gestione Preventivi',
      'createdAt': DateTime.now().toIso8601String(),
      'clienti': await db.query('clienti'),
      'prodotti': await db.query('prodotti'),
      'preventivi': await db.query('preventivi'),
      'rate': await db.query('rate'),
    };
  }

  Future<File> createAutomaticBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'backup'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);
    final file = File(p.join(backupDir.path, 'preventivi_auto_backup.json'));
    await file.writeAsString(jsonEncode(await _backupData()), flush: true);
    return file;
  }

  Future<File> exportBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(dir.path, 'backup_export'));
    if (!await exports.exists()) await exports.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(exports.path, 'Preventivi_backup_$stamp.json'));
    await file.writeAsString(jsonEncode(await _backupData()), flush: true);
    return file;
  }

  Future<void> importBackup(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup non valido.');
    }
    final clienti = List<Map<String, dynamic>>.from(
      (decoded['clienti'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final prodotti = List<Map<String, dynamic>>.from(
      (decoded['prodotti'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final preventivi = List<Map<String, dynamic>>.from(
      (decoded['preventivi'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final rate = List<Map<String, dynamic>>.from(
      (decoded['rate'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('rate');
      await txn.delete('preventivi');
      await txn.delete('prodotti');
      await txn.delete('clienti');
      for (final row in clienti) await txn.insert('clienti', row);
      for (final row in prodotti) await txn.insert('prodotti', row);
      for (final row in preventivi) await txn.insert('preventivi', row);
      for (final row in rate) await txn.insert('rate', row);
    });
    await createAutomaticBackup();
  }

  Future<void> autoBackup() async {
    try {
      await createAutomaticBackup();
    } catch (_) {}
  }

}
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<AndroidFlutterLocalNotificationsPlugin?> _android() async {
    return _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
  }

  Future<bool> richiediPermessi() async {
    final android = await _android();
    if (android == null) return false;

    final notifiche = await android.requestNotificationsPermission() ?? false;
    await android.requestExactAlarmsPermission();
    return notifiche;
  }

  Future<bool> notificheAbilitate() async {
    final android = await _android();
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    } catch (_) {}

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _notifications.initialize(settings);
    await richiediPermessi();
  }

  Future<bool> programmaNotificaRata({
    required int id,
    required String cliente,
    required double importo,
    required DateTime dataScadenza,
  }) async {
    final when = tz.TZDateTime.from(dataScadenza, tz.local);

    if (when.isBefore(tz.TZDateTime.now(tz.local))) return false;

    try {
      await _notifications.zonedSchedule(
        id,
        'Rata in scadenza',
        'Oggi scade la rata di €${importo.toStringAsFixed(2)} per $cliente.',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'rate_channel',
            'Notifiche Rate',
            channelDescription: 'Avvisi per le scadenze dei pagamenti rateali',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (_) {
      // Se l'utente non concede gli allarmi esatti, usa il fallback inexact.
      try {
        await _notifications.zonedSchedule(
          id,
          'Rata in scadenza',
          'Oggi scade la rata di €${importo.toStringAsFixed(2)} per $cliente.',
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'rate_channel',
              'Notifiche Rate',
              channelDescription:
                  'Avvisi per le scadenze dei pagamenti rateali',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}

class PdfGenerator {
  static Future<void> generaECondividiPreventivo({
    required String numero,
    required String cliente,
    required List<Map<String, dynamic>> articoli,
    required int numeroRate,
    required double ivaPercent,
  }) async {
    final pdf = pw.Document();

    // Font TrueType con supporto completo del simbolo €.
    // I font PDF standard possono non rendere correttamente il carattere Euro
    // in alcuni visualizzatori PDF.
    final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final pdfFont = pw.Font.ttf(fontData);
    final pdfBoldFont = pw.Font.ttf(boldFontData);
    final pdfTheme = pw.ThemeData.withFont(
      base: pdfFont,
      bold: pdfBoldFont,
    );

    pw.MemoryImage? logo;
    Map<String, dynamic>? datiCliente;

    try {
      final bytes = await rootBundle.load('assets/logo.png');
      logo = pw.MemoryImage(Uint8List.fromList(bytes.buffer.asUint8List()));
    } catch (_) {}

    // Recupera l'anagrafica completa per stampare tutti i dati del cliente.
    try {
      final clienti = await DatabaseHelper.instance.getClienti();
      final matches = clienti.where(
        (c) => (c['nome'] ?? '').toString().trim() == cliente.trim(),
      );
      if (matches.isNotEmpty) {
        datiCliente = Map<String, dynamic>.from(matches.first);
      }
    } catch (_) {}

    final imponibile = articoli.fold<double>(
      0,
      (sum, x) {
        final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
        final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
        return sum + (prezzo * quantita);
      },
    );
    final iva = imponibile * ivaPercent / 100;
    final totale = imponibile + iva;
    final quota = numeroRate > 0 ? totale / numeroRate : totale;
    final data = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final gold = PdfColor.fromHex('#B8860B');
    final dark = PdfColor.fromHex('#1E293B');

    String value(String key) => (datiCliente?[key] ?? '').toString().trim();

    final indirizzo = value('indirizzo');
    final telefono = value('telefono');
    final email = value('email');
    final partitaIva = value('partita_iva');
    final codiceFiscale = value('codice_fiscale');

    final clientRows = <pw.Widget>[
      pw.Text(
        'CLIENTE',
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: gold,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        cliente,
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      if (indirizzo.isNotEmpty) pw.Text('Indirizzo: $indirizzo'),
      if (telefono.isNotEmpty) pw.Text('Telefono: $telefono'),
      if (email.isNotEmpty) pw.Text('Email: $email'),
      if (partitaIva.isNotEmpty) pw.Text('Partita IVA: $partitaIva'),
      if (codiceFiscale.isNotEmpty) pw.Text('Codice Fiscale: $codiceFiscale'),
    ];

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
        build: (_) => [
          // Logo ingrandito: circa il doppio rispetto alla versione precedente.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.SizedBox(
                  width: 285,
                  height: 190,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                )
              else
                pw.SizedBox(
                  width: 285,
                  height: 150,
                  child: pw.Text(
                    'BTS',
                    style: pw.TextStyle(
                      fontSize: 38,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(width: 18),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'PREVENTIVO',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Divider(color: gold),
                    pw.SizedBox(height: 8),
                    pw.Text('N. $numero', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Data: $data', style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: clientRows,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['N.', 'Prodotto / Servizio', 'Q.tà', 'Prezzo unit. (€)', 'Totale (€)'],
            data: [
              for (var i = 0; i < articoli.length; i++)
                [
                  '${i + 1}',
                  (articoli[i]['nome'] ?? '').toString(),
                  ((articoli[i]['quantita'] as num?)?.toDouble() ?? 1).toStringAsFixed(2),
                  '€ ${((articoli[i]['prezzo'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  '€ ${(((articoli[i]['prezzo'] as num?)?.toDouble() ?? 0) * ((articoli[i]['quantita'] as num?)?.toDouble() ?? 1)).toStringAsFixed(2)}',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: dark),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(25),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FixedColumnWidth(42),
              3: const pw.FixedColumnWidth(75),
              4: const pw.FixedColumnWidth(75),
            },
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Imponibile: € ${imponibile.toStringAsFixed(2)}'),
                if (ivaPercent == 0)
                  pw.Text(
                    'FUORI CAMPO IVA FCI',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  )
                else
                  pw.Text(
                    'IVA ${ivaPercent.toStringAsFixed(0)}%: € ${iva.toStringAsFixed(2)}',
                  ),
                pw.SizedBox(height: 5),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: gold,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: pw.Text(
                    'TOTALE: € ${totale.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (numeroRate > 1) ...[
            pw.SizedBox(height: 18),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gold),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Text(
                '$numeroRate rate mensili da € ${quota.toStringAsFixed(2)} ciascuna.',
              ),
            ),
          ],
          pw.SizedBox(height: 25),
          pw.Divider(color: gold),
          pw.SizedBox(height: 6),
          pw.Text(
            'Documento generato da Gestione Preventivi.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Preventivo_$numero.pdf',
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int preventivi = 0;
  int clienti = 0;
  int prodotti = 0;
  int rate = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    caricaStatistiche();
  }

  Future<void> caricaStatistiche() async {
    final db = DatabaseHelper.instance;

    final results = await Future.wait([
      db.getPreventivi(),
      db.getClienti(),
      db.getProdotti(),
      db.getRate(),
    ]);

    if (!mounted) return;

    setState(() {
      preventivi = results[0].length;
      clienti = results[1].length;
      prodotti = results[2].length;
      rate = results[3].length;
      loading = false;
    });
  }

  Future<void> apri(Widget pagina) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => pagina),
    );
    caricaStatistiche();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Preventivi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: caricaStatistiche,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: primary,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/logo.png',
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Gestione Preventivi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Crea, salva e condividi i tuoi preventivi.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: primary,
                        ),
                        onPressed: () =>
                            apri(const NuovoPreventivoScreen()),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'NUOVO PREVENTIVO',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    Icons.receipt_long,
                    'Preventivi',
                    preventivi,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    Icons.people_alt_outlined,
                    'Clienti',
                    clienti,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    Icons.inventory_2_outlined,
                    'Prodotti',
                    prodotti,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    Icons.payments_outlined,
                    'Rate',
                    rate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Gestione',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _menuTile(
              Icons.receipt_long,
              'Lista preventivi',
              'Visualizza i preventivi salvati',
              () => apri(const ListaPreventiviScreen()),
            ),
            _menuTile(
              Icons.people_alt_outlined,
              'Clienti',
              'Gestisci l’anagrafica clienti',
              () => apri(const ClientiScreen()),
            ),
            _menuTile(
              Icons.inventory_2_outlined,
              'Prodotti / Servizi',
              'Gestisci prodotti e prezzi',
              () => apri(const ProdottiScreen()),
            ),
            _menuTile(
              Icons.payments_outlined,
              'Rate e scadenze',
              'Controlla le rate programmate',
              () => apri(const RateScreen()),
            ),
            _menuTile(
              Icons.backup_outlined,
              'Backup e dati',
              'Esporta, importa e gestisci il backup',
              () => apri(const BackupScreen()),
            ),
            _menuTile(
              Icons.notifications_active_outlined,
              'Notifiche',
              'Abilita gli avvisi delle scadenze',
              () => apri(const NotificheScreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, int value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          children: [
            Icon(
              icon,
              size: 30,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 7),
            Text(
              loading ? '…' : '$value',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}


Future<String?> selezionaCliente(BuildContext context) async {
  final clienti = await DatabaseHelper.instance.getClienti();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final filtrati = clienti.where((c) {
            final q = query.toLowerCase();
            final nome = (c['nome'] ?? '').toString().toLowerCase();
            final piva = (c['partita_iva'] ?? '').toString().toLowerCase();
            final cf = (c['codice_fiscale'] ?? '').toString().toLowerCase();
            return nome.contains(q) || piva.contains(q) || cf.contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Seleziona cliente'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Cerca cliente',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: filtrati.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Nessun cliente trovato.'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtrati.length,
                            itemBuilder: (_, i) => ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(filtrati[i]['nome']),
                              subtitle: Text(
                                [
                                  filtrati[i]['telefono'],
                                  filtrati[i]['email'],
                                ]
                                    .where((x) => (x ?? '').toString().isNotEmpty)
                                    .join(' • '),
                              ),
                              onTap: () => Navigator.pop(
                                dialogContext,
                                filtrati[i]['nome'].toString(),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ANNULLA'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<Map<String, dynamic>?> selezionaProdotto(BuildContext context) async {
  final prodotti = await DatabaseHelper.instance.getProdotti();
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final filtrati = prodotti.where((p) {
            final nome = (p['nome'] ?? '').toString().toLowerCase();
            return nome.contains(query.toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Seleziona prodotto / servizio'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Cerca servizio',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: filtrati.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Nessun servizio trovato.'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtrati.length,
                            itemBuilder: (_, i) => ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(filtrati[i]['nome']),
                              trailing: Text(
                                '€ ${(filtrati[i]['prezzo'] as num).toDouble().toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () => Navigator.pop(
                                dialogContext,
                                Map<String, dynamic>.from(filtrati[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ANNULLA'),
              ),
            ],
          );
        },
      );
    },
  );
}

class NuovoPreventivoScreen extends StatefulWidget {
  const NuovoPreventivoScreen({super.key});

  @override
  State<NuovoPreventivoScreen> createState() => _NuovoPreventivoScreenState();
}

class _NuovoPreventivoScreenState extends State<NuovoPreventivoScreen> {
  final clienteController = TextEditingController();
  final prodottoController = TextEditingController();
  final prezzoController = TextEditingController();
  final quantitaController = TextEditingController(text: '1');

  final List<Map<String, dynamic>> articoli = [];

  int numeroRate = 1;
  double ivaPercent = 22;
  bool busy = false;

  double get imponibile => articoli.fold<double>(
        0,
        (sum, x) {
          final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
          final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
          return sum + (prezzo * quantita);
        },
      );

  double get iva => imponibile * ivaPercent / 100;

  double get totale => imponibile + iva;

  Future<void> scegliCliente() async {
    final nome = await selezionaCliente(context);
    if (nome != null && mounted) {
      setState(() => clienteController.text = nome);
    }
  }

  Future<void> scegliServizio() async {
    final prodotto = await selezionaProdotto(context);
    if (prodotto != null && mounted) {
      setState(() {
        prodottoController.text = prodotto['nome'].toString();
        prezzoController.text =
            (prodotto['prezzo'] as num).toDouble().toStringAsFixed(2);
        quantitaController.text = '1';
      });
    }
  }

  @override
  void dispose() {
    clienteController.dispose();
    prodottoController.dispose();
    prezzoController.dispose();
    quantitaController.dispose();
    super.dispose();
  }

  void aggiungiProdotto() {
    final nome = prodottoController.text.trim();
    final prezzo = double.tryParse(
      prezzoController.text.trim().replaceAll(',', '.'),
    );
    final quantita = double.tryParse(
      quantitaController.text.trim().replaceAll(',', '.'),
    );

    if (nome.isEmpty || prezzo == null || prezzo < 0 || quantita == null || quantita <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci descrizione, prezzo e quantità validi.'),
        ),
      );
      return;
    }

    setState(() {
      articoli.add({'nome': nome, 'prezzo': prezzo, 'quantita': quantita});
      prodottoController.clear();
      prezzoController.clear();
      quantitaController.text = '1';
    });
  }

  Future<void> generaPreventivo() async {
    if (busy) return;

    final cliente = clienteController.text.trim();

    if (cliente.isEmpty || articoli.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci il cliente e almeno un prodotto.'),
        ),
      );
      return;
    }

    setState(() => busy = true);

    try {
      final db = DatabaseHelper.instance;
      final numero = await db.prossimoNumeroPreventivo();

      final id = await db.insertPreventivo(
        numero: numero,
        cliente: cliente,
        totale: totale,
        numeroRate: numeroRate,
        articoli: articoli,
        ivaPercent: ivaPercent,
      );

      final clienti = await db.getClienti();

      if (!clienti.any(
        (c) =>
            (c['nome'] as String).toLowerCase() ==
            cliente.toLowerCase(),
      )) {
        await db.insertCliente(nome: cliente);
      }

      if (numeroRate > 1) {
        final base = totale / numeroRate;
        double somma = 0;

        for (int i = 1; i <= numeroRate; i++) {
          final data = DateTime(
            DateTime.now().year,
            DateTime.now().month + i,
            DateTime.now().day,
            9,
          );

          final importo = i == numeroRate
              ? double.parse((totale - somma).toStringAsFixed(2))
              : double.parse(base.toStringAsFixed(2));

          somma += importo;

          await db.insertRata(
            preventivoId: id,
            cliente: cliente,
            importo: importo,
            dataScadenza: data,
          );

          await NotificationService().programmaNotificaRata(
            id: id * 100 + i,
            cliente: cliente,
            importo: importo,
            dataScadenza: data,
          );
        }
      }

      await PdfGenerator.generaECondividiPreventivo(
        numero: numero,
        cliente: cliente,
        articoli: articoli,
        numeroRate: numeroRate,
        ivaPercent: ivaPercent,
      );

      final notificheOk = await NotificationService().notificheAbilitate();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notificheOk
                  ? 'Preventivo $numero salvato e scadenze programmate.'
                  : 'Preventivo $numero salvato. Abilita le notifiche per ricevere gli avvisi.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget _riepilogoRiga(
    String label,
    double value, {
    bool bold = false,
    double size = 16,
  }) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('€ ${value.toStringAsFixed(2)}', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nuovo Preventivo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dati Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: clienteController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome / Ragione Sociale',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliCliente,
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('SELEZIONA DALL’ANAGRAFICA'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Prodotti / Servizi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: prodottoController,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: quantitaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantità',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: prezzoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo unitario €',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: aggiungiProdotto,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliServizio,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('SCEGLI DA PRODOTTI / SERVIZI'),
              ),
            ),
            const SizedBox(height: 12),
            if (articoli.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: articoli.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final prezzo = (articoli[i]['prezzo'] as num?)?.toDouble() ?? 0;
                    final quantita = (articoli[i]['quantita'] as num?)?.toDouble() ?? 1;
                    final riga = prezzo * quantita;
                    return ListTile(
                      title: Text(articoli[i]['nome'].toString()),
                      subtitle: Text(
                        'Quantità: ${quantita.toStringAsFixed(2)}  •  Prezzo unitario: € ${prezzo.toStringAsFixed(2)}  •  Totale: € ${riga.toStringAsFixed(2)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => articoli.removeAt(i));
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _riepilogoRiga('Imponibile', imponibile),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'IVA',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        DropdownButton<double>(
                          value: ivaPercent,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Esente / 0%')),
                            DropdownMenuItem(value: 4, child: Text('4%')),
                            DropdownMenuItem(value: 5, child: Text('5%')),
                            DropdownMenuItem(value: 10, child: Text('10%')),
                            DropdownMenuItem(value: 22, child: Text('22%')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => ivaPercent = v);
                          },
                        ),
                        Text(ivaPercent == 0 ? 'FUORI CAMPO IVA FCI' : '€ ${iva.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(),
                    _riepilogoRiga(
                      'TOTALE',
                      totale,
                      bold: true,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Numero rate mensili',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<int>(
                  value: numeroRate,
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        '${i + 1} ${i == 0 ? 'rata' : 'rate'}',
                      ),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => numeroRate = v);
                    }
                  },
                ),
              ],
            ),
            if (numeroRate > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Rata indicativa: € '
                  '${(totale / numeroRate).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: busy ? null : generaPreventivo,
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  busy
                      ? 'SALVATAGGIO...'
                      : 'GENERA PDF E PROGRAMMA RATE',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ListaPreventiviScreen extends StatefulWidget {
  const ListaPreventiviScreen({super.key});

  @override
  State<ListaPreventiviScreen> createState() =>
      _ListaPreventiviScreenState();
}

class _ListaPreventiviScreenState extends State<ListaPreventiviScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> preventivi = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _carica();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final data = await DatabaseHelper.instance.getPreventivi();

    if (mounted) {
      setState(() {
        preventivi = data;
        loading = false;
      });
    }
  }

  Future<void> _elimina(Map<String, dynamic> preventivo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare preventivo?'),
        content: Text(
          'Vuoi eliminare ${preventivo['numero']} '
          'del cliente "${preventivo['cliente']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final db = await DatabaseHelper.instance.database;

      await db.delete(
        'rate',
        where: 'preventivo_id = ?',
        whereArgs: [preventivo['id']],
      );

      await db.delete(
        'preventivi',
        where: 'id = ?',
        whereArgs: [preventivo['id']],
      );

      await _carica();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preventivo eliminato.')),
        );
      }
    }
  }

  void _mostraDettagli(Map<String, dynamic> x) {
    final data = DateTime.parse(x['data']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 25,
                    child: Icon(Icons.receipt_long),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      x['numero'],
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 28),
              _detailRow(Icons.person_outline, 'Cliente', x['cliente']),
              _detailRow(
                Icons.calendar_today_outlined,
                'Data',
                DateFormat('dd/MM/yyyy').format(data),
              ),
              _detailRow(
                Icons.payments_outlined,
                'Totale',
                '€ ${(x['totale'] as num).toStringAsFixed(2)}',
              ),
              _detailRow(
                Icons.event_repeat,
                'Rate',
                '${x['numero_rate']} '
                '${x['numero_rate'] == 1 ? 'rata' : 'rate'}',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ModificaPreventivoScreen(preventivo: x),
                          ),
                        ).then((_) => _carica());
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('MODIFICA'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _elimina(x);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('ELIMINA'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await PdfGenerator.generaECondividiPreventivo(
                      numero: x['numero'],
                      cliente: x['cliente'],
                      articoli: _articoliDaPreventivo(x),
                      numeroRate: x['numero_rate'],
                      ivaPercent: (x['iva_percent'] as num?)?.toDouble() ?? 0,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('RIGENERA / CONDIVIDI PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _articoliDaPreventivo(
    Map<String, dynamic> x,
  ) {
    try {
      final raw = jsonDecode((x['articoli'] ?? '[]').toString());

      return (raw as List).map((e) {
        return {
          'nome': e['nome'].toString(),
          'prezzo': (e['prezzo'] as num).toDouble(),
          'quantita': (e['quantita'] as num?)?.toDouble() ?? 1,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    final filtrati = preventivi.where((x) {
      if (q.isEmpty) return true;

      final numero = (x['numero'] ?? '').toString().toLowerCase();
      final cliente = (x['cliente'] ?? '').toString().toLowerCase();

      return numero.contains(q) || cliente.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lista Preventivi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _carica,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carica,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cerca numero o cliente',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (filtrati.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${filtrati.length} '
                        '${filtrati.length == 1 ? 'preventivo' : 'preventivi'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (filtrati.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nessun preventivo salvato.'
                                : 'Nessun preventivo trovato.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ...filtrati.map((x) {
                    final data = DateTime.parse(x['data']);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 9),
                      child: ListTile(
                        onTap: () => _mostraDettagli(x),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long),
                        ),
                        title: Text(
                          x['numero'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${x['cliente']}\n'
                            '${DateFormat('dd/MM/yyyy').format(data)} • '
                            '${x['numero_rate']} '
                            '${x['numero_rate'] == 1 ? 'rata' : 'rate'}',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '€ ${(x['totale'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class ModificaPreventivoScreen extends StatefulWidget {
  final Map<String, dynamic> preventivo;

  const ModificaPreventivoScreen({
    super.key,
    required this.preventivo,
  });

  @override
  State<ModificaPreventivoScreen> createState() =>
      _ModificaPreventivoScreenState();
}

class _ModificaPreventivoScreenState
    extends State<ModificaPreventivoScreen> {
  late final TextEditingController clienteController;

  final prodottoController = TextEditingController();
  final prezzoController = TextEditingController();
  final quantitaController = TextEditingController(text: '1');

  late List<Map<String, dynamic>> articoli;
  late int numeroRate;
  late double ivaPercent;

  bool busy = false;

  double get imponibile => articoli.fold<double>(
        0,
        (sum, x) {
          final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
          final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
          return sum + (prezzo * quantita);
        },
      );

  double get iva => imponibile * ivaPercent / 100;

  double get totale => imponibile + iva;

  Future<void> scegliCliente() async {
    final nome = await selezionaCliente(context);
    if (nome != null && mounted) {
      setState(() => clienteController.text = nome);
    }
  }

  Future<void> scegliServizio() async {
    final prodotto = await selezionaProdotto(context);
    if (prodotto != null && mounted) {
      setState(() {
        prodottoController.text = prodotto['nome'].toString();
        prezzoController.text =
            (prodotto['prezzo'] as num).toDouble().toStringAsFixed(2);
        quantitaController.text = '1';
      });
    }
  }

  @override
  void initState() {
    super.initState();

    clienteController = TextEditingController(
      text: widget.preventivo['cliente'],
    );

    numeroRate =
        (widget.preventivo['numero_rate'] as num).toInt();
    ivaPercent =
        (widget.preventivo['iva_percent'] as num?)?.toDouble() ?? 0;

    try {
      final raw = jsonDecode(
        (widget.preventivo['articoli'] ?? '[]').toString(),
      );

      articoli = (raw as List).map((e) {
        return {
          'nome': e['nome'].toString(),
          'prezzo': (e['prezzo'] as num).toDouble(),
        };
      }).toList();
    } catch (_) {
      articoli = [];
    }
  }

  @override
  void dispose() {
    clienteController.dispose();
    prodottoController.dispose();
    prezzoController.dispose();
    quantitaController.dispose();
    super.dispose();
  }

  void aggiungi() {
    final nome = prodottoController.text.trim();
    final prezzo = double.tryParse(
      prezzoController.text.trim().replaceAll(',', '.'),
    );
    final quantita = double.tryParse(
      quantitaController.text.trim().replaceAll(',', '.'),
    );

    if (nome.isEmpty || prezzo == null || prezzo < 0 || quantita == null || quantita <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci descrizione, prezzo e quantità validi.'),
        ),
      );
      return;
    }

    setState(() {
      articoli.add({'nome': nome, 'prezzo': prezzo, 'quantita': quantita});
      prodottoController.clear();
      prezzoController.clear();
      quantitaController.text = '1';
    });
  }

  Future<void> salva() async {
    if (busy) return;

    final cliente = clienteController.text.trim();

    if (cliente.isEmpty || articoli.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci il cliente e almeno un prodotto.'),
        ),
      );
      return;
    }

    setState(() => busy = true);

    try {
      final db = DatabaseHelper.instance;
      final preventivoId =
          (widget.preventivo['id'] as num).toInt();

      await db.updatePreventivo(
        id: preventivoId,
        cliente: cliente,
        totale: totale,
        numeroRate: numeroRate,
        articoli: articoli,
        ivaPercent: ivaPercent,
      );

      final database = await db.database;

      await database.delete(
        'rate',
        where: 'preventivo_id = ?',
        whereArgs: [preventivoId],
      );

      if (numeroRate > 1) {
        final base = totale / numeroRate;
        double somma = 0;

        for (int i = 1; i <= numeroRate; i++) {
          final data = DateTime(
            DateTime.now().year,
            DateTime.now().month + i,
            DateTime.now().day,
            9,
          );

          final importo = i == numeroRate
              ? double.parse((totale - somma).toStringAsFixed(2))
              : double.parse(base.toStringAsFixed(2));

          somma += importo;

          await db.insertRata(
            preventivoId: preventivoId,
            cliente: cliente,
            importo: importo,
            dataScadenza: data,
          );

          await NotificationService().programmaNotificaRata(
            id: preventivoId * 100 + i,
            cliente: cliente,
            importo: importo,
            dataScadenza: data,
          );
        }
      }

      await PdfGenerator.generaECondividiPreventivo(
        numero: widget.preventivo['numero'],
        cliente: cliente,
        articoli: articoli,
        numeroRate: numeroRate,
        ivaPercent: ivaPercent,
      );

      final notificheOk = await NotificationService().notificheAbilitate();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notificheOk
                  ? 'Preventivo modificato, PDF rigenerato e scadenze programmate.'
                  : 'Preventivo modificato. Abilita le notifiche per ricevere gli avvisi.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget _riepilogoRiga(
    String label,
    double value, {
    bool bold = false,
    double size = 16,
  }) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('€ ${value.toStringAsFixed(2)}', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Modifica ${widget.preventivo['numero']}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dati Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: clienteController,
              decoration: const InputDecoration(
                labelText: 'Nome / Ragione Sociale',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliCliente,
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('SELEZIONA DALL’ANAGRAFICA'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Prodotti / Servizi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: prodottoController,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: quantitaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantità',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: prezzoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo unitario €',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: aggiungi,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliServizio,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('SCEGLI DA PRODOTTI / SERVIZI'),
              ),
            ),
            const SizedBox(height: 12),
            if (articoli.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: articoli.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final prezzo = (articoli[i]['prezzo'] as num?)?.toDouble() ?? 0;
                    final quantita = (articoli[i]['quantita'] as num?)?.toDouble() ?? 1;
                    final riga = prezzo * quantita;
                    return ListTile(
                      title: Text(articoli[i]['nome'].toString()),
                      subtitle: Text(
                        'Quantità: ${quantita.toStringAsFixed(2)}  •  Prezzo unitario: € ${prezzo.toStringAsFixed(2)}  •  Totale: € ${riga.toStringAsFixed(2)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => articoli.removeAt(i));
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _riepilogoRiga('Imponibile', imponibile),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'IVA',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        DropdownButton<double>(
                          value: ivaPercent,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Esente / 0%')),
                            DropdownMenuItem(value: 4, child: Text('4%')),
                            DropdownMenuItem(value: 5, child: Text('5%')),
                            DropdownMenuItem(value: 10, child: Text('10%')),
                            DropdownMenuItem(value: 22, child: Text('22%')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => ivaPercent = v);
                          },
                        ),
                        Text(ivaPercent == 0 ? 'FUORI CAMPO IVA FCI' : '€ ${iva.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(),
                    _riepilogoRiga(
                      'TOTALE',
                      totale,
                      bold: true,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Numero rate mensili',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<int>(
                  value: numeroRate,
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        '${i + 1} ${i == 0 ? 'rata' : 'rate'}',
                      ),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => numeroRate = v);
                    }
                  },
                ),
              ],
            ),
            if (numeroRate > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Rata indicativa: € '
                  '${(totale / numeroRate).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: busy ? null : salva,
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  busy
                      ? 'SALVATAGGIO...'
                      : 'SALVA E RIGENERA PDF',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClientiScreen extends StatefulWidget {
  const ClientiScreen({super.key});

  @override
  State<ClientiScreen> createState() => _ClientiScreenState();
}

class _ClientiScreenState extends State<ClientiScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> clienti = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final data = await DatabaseHelper.instance.getClienti();

    if (mounted) {
      setState(() {
        clienti = data;
        loading = false;
      });
    }
  }

  Future<void> _formCliente([Map<String, dynamic>? cliente]) async {
    final nome = TextEditingController(text: cliente?['nome'] ?? '');
    final telefono =
        TextEditingController(text: cliente?['telefono'] ?? '');
    final email = TextEditingController(text: cliente?['email'] ?? '');
    final indirizzo =
        TextEditingController(text: cliente?['indirizzo'] ?? '');
    final partitaIva =
        TextEditingController(text: cliente?['partita_iva'] ?? '');
    final codiceFiscale =
        TextEditingController(text: cliente?['codice_fiscale'] ?? '');
    final key = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente == null ? 'Nuovo cliente' : 'Modifica cliente',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome / Ragione Sociale',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Inserisci il nome'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: indirizzo,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: partitaIva,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Partita IVA',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codiceFiscale,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Codice Fiscale',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (!key.currentState!.validate()) return;

                      if (cliente == null) {
                        await DatabaseHelper.instance.insertCliente(
                          nome: nome.text.trim(),
                          telefono: telefono.text.trim(),
                          email: email.text.trim(),
                          indirizzo: indirizzo.text.trim(),
                          partitaIva: partitaIva.text.trim(),
                          codiceFiscale: codiceFiscale.text.trim(),
                        );
                      } else {
                        await DatabaseHelper.instance.updateCliente(
                          id: cliente['id'],
                          nome: nome.text.trim(),
                          telefono: telefono.text.trim(),
                          email: email.text.trim(),
                          indirizzo: indirizzo.text.trim(),
                          partitaIva: partitaIva.text.trim(),
                          codiceFiscale: codiceFiscale.text.trim(),
                        );
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      await _carica();
                    },
                    icon: const Icon(Icons.save),
                    label: Text(
                      cliente == null
                          ? 'SALVA CLIENTE'
                          : 'SALVA MODIFICHE',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nome.dispose();
    telefono.dispose();
    email.dispose();
    indirizzo.dispose();
    partitaIva.dispose();
    codiceFiscale.dispose();
    email.dispose();
    indirizzo.dispose();
  }

  Future<void> _elimina(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare cliente?'),
        content: Text('Vuoi eliminare "${c['nome']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DatabaseHelper.instance.deleteCliente(c['id']);
      await _carica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    final filtrati = clienti.where((c) {
      return '${c['nome']} ${c['telefono']} ${c['email']}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clienti'),
        actions: [
          IconButton(
            onPressed: _carica,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formCliente(),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo cliente'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carica,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cerca cliente',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (filtrati.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.people_alt_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nessun cliente salvato.'
                                : 'Nessun cliente trovato.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ...filtrati.map((c) {
                    final dettagli = [
                      if ((c['telefono'] ?? '').toString().isNotEmpty)
                        c['telefono'],
                      if ((c['email'] ?? '').toString().isNotEmpty)
                        c['email'],
                      if ((c['indirizzo'] ?? '').toString().isNotEmpty)
                        c['indirizzo'],
                    ].join('\n');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          c['nome'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(dettagli),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _formCliente(c);
                            } else {
                              _elimina(c);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: Icon(Icons.edit),
                                title: Text('Modifica'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Elimina'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class ProdottiScreen extends StatefulWidget {
  const ProdottiScreen({super.key});

  @override
  State<ProdottiScreen> createState() => _ProdottiScreenState();
}

class _ProdottiScreenState extends State<ProdottiScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> prodotti = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final data = await DatabaseHelper.instance.getProdotti();

    if (mounted) {
      setState(() {
        prodotti = data;
        loading = false;
      });
    }
  }

  Future<void> _formProdotto([Map<String, dynamic>? prodotto]) async {
    final nome = TextEditingController(text: prodotto?['nome'] ?? '');

    final prezzo = TextEditingController(
      text: prodotto == null
          ? ''
          : (prodotto['prezzo'] as num).toStringAsFixed(2),
    );

    final key = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prodotto == null
                      ? 'Nuovo prodotto / servizio'
                      : 'Modifica prodotto / servizio',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: nome,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nome prodotto / servizio',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Inserisci il nome'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: prezzo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Prezzo €',
                    prefixIcon: Icon(Icons.euro),
                  ),
                  validator: (v) {
                    final value = double.tryParse(
                      (v ?? '').trim().replaceAll(',', '.'),
                    );

                    if (value == null || value < 0) {
                      return 'Inserisci un prezzo valido';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (!key.currentState!.validate()) return;

                      final value = double.parse(
                        prezzo.text.trim().replaceAll(',', '.'),
                      );

                      if (prodotto == null) {
                        await DatabaseHelper.instance.insertProdotto(
                          nome: nome.text.trim(),
                          prezzo: value,
                        );
                      } else {
                        await DatabaseHelper.instance.updateProdotto(
                          id: prodotto['id'],
                          nome: nome.text.trim(),
                          prezzo: value,
                        );
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      await _carica();
                    },
                    icon: const Icon(Icons.save),
                    label: Text(
                      prodotto == null
                          ? 'SALVA PRODOTTO'
                          : 'SALVA MODIFICHE',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nome.dispose();
    prezzo.dispose();
  }

  Future<void> _elimina(Map<String, dynamic> prodotto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare prodotto?'),
        content: Text('Vuoi eliminare "${prodotto['nome']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DatabaseHelper.instance.deleteProdotto(prodotto['id']);
      await _carica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    final filtrati = prodotti.where((prodotto) {
      return (prodotto['nome'] ?? '')
          .toString()
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prodotti / Servizi'),
        actions: [
          IconButton(
            onPressed: _carica,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formProdotto(),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo prodotto / servizio'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carica,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cerca prodotto / servizio',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (q.isEmpty && filtrati.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${filtrati.length} prodotti / servizi',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (filtrati.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nessun prodotto o servizio salvato.'
                                : 'Nessun prodotto trovato.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          if (q.isEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _formProdotto(),
                              icon: const Icon(Icons.add),
                              label: const Text(
                                'Aggiungi il primo prodotto',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ...filtrati.map((prodotto) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(
                          prodotto['nome'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text('Prezzo di listino'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '€ ${(prodotto['prezzo'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _formProdotto(prodotto);
                                } else {
                                  _elimina(prodotto);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Modifica'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Elimina'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}



class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  String? lastMessage;

  Future<void> _esporta() async {
    setState(() => busy = true);
    try {
      final file = await DatabaseHelper.instance.exportBackup();
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Backup Preventivi',
        text: 'Backup clienti, servizi e preventivi.',
      );
      if (mounted) setState(() => lastMessage = 'Backup esportato correttamente.');
    } catch (e) {
      if (mounted) setState(() => lastMessage = 'Errore esportazione: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _importa() async {
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() => busy = false);
        return;
      }
      if (!mounted) return;
      final conferma = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importa backup'),
          content: const Text(
            'L’importazione sostituirà i dati attuali di clienti, servizi, preventivi e rate. Continuare?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('IMPORTA')),
          ],
        ),
      );
      if (conferma != true) return;
      await DatabaseHelper.instance.importBackup(File(result.files.single.path!));
      if (mounted) setState(() => lastMessage = 'Backup importato correttamente.');
    } catch (e) {
      if (mounted) setState(() => lastMessage = 'Backup non valido: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _creaAutomatico() async {
    setState(() => busy = true);
    try {
      final file = await DatabaseHelper.instance.createAutomaticBackup();
      if (mounted) setState(() => lastMessage = 'Backup automatico aggiornato.');
      debugPrint('Backup automatico: ${file.path}');
    } catch (e) {
      if (mounted) setState(() => lastMessage = 'Errore backup automatico: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup e dati')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('Backup automatico'),
              subtitle: const Text('Viene aggiornato automaticamente dopo ogni modifica dei dati.'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: busy ? null : _creaAutomatico,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _esporta,
            icon: const Icon(Icons.ios_share),
            label: const Text('ESPORTA BACKUP'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _importa,
            icon: const Icon(Icons.file_open),
            label: const Text('IMPORTA BACKUP'),
          ),
          if (busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (lastMessage != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(lastMessage!),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Il backup contiene clienti, prodotti/servizi, preventivi e rate. L’importazione sostituisce i dati presenti sul dispositivo.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class NotificheScreen extends StatefulWidget {
  const NotificheScreen({super.key});

  @override
  State<NotificheScreen> createState() => _NotificheScreenState();
}

class _NotificheScreenState extends State<NotificheScreen> {
  bool? abilitate;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _aggiorna();
  }

  Future<void> _aggiorna() async {
    final stato = await NotificationService().notificheAbilitate();
    if (!mounted) return;
    setState(() {
      abilitate = stato;
      loading = false;
    });
  }

  Future<void> _abilita() async {
    setState(() => loading = true);
    await NotificationService().richiediPermessi();
    await _aggiorna();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifiche e scadenze')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              abilitate == true
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              size: 70,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              loading
                  ? 'Controllo autorizzazioni...'
                  : abilitate == true
                      ? 'Notifiche abilitate'
                      : 'Notifiche non abilitate',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              abilitate == true
                  ? 'Le scadenze delle rate possono essere segnalate automaticamente.'
                  : 'Per ricevere gli avvisi delle rate, abilita le notifiche per questa app nelle impostazioni di Android.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: loading ? null : _abilita,
              icon: const Icon(Icons.notifications_active),
              label: const Text('ABILITA / RICHIEDI PERMESSI'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nota: Android può richiedere anche il permesso per gli allarmi esatti. Se viene negato, l’app utilizza comunque il sistema di notifica non esatto quando possibile.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class RateScreen extends StatelessWidget {
  const RateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate e scadenze'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getRate(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final rate = snapshot.data!;

          if (rate.isEmpty) {
            return const _EmptyState(
              icon: Icons.payments_outlined,
              text: 'Nessuna rata programmata.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rate.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final x = rate[index];

              final data = DateTime.parse(
                x['data_scadenza'],
              );

              final pagata = x['pagata'] == 1;

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      pagata
                          ? Icons.check
                          : Icons.schedule,
                    ),
                  ),
                  title: Text(
                    x['cliente'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Scadenza: '
                    '${DateFormat('dd/MM/yyyy').format(data)}',
                  ),
                  trailing: Text(
                    '€ ${(x['importo'] as num).toStringAsFixed(2)}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 15),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
