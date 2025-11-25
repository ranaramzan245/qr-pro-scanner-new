// lib/main.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  runApp(const QRProApp());
}

class QRProApp extends StatelessWidget {
  const QRProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'qr pro scanner',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF0A74FF),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0A74FF)),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScanEntry {
  final String text;
  final DateTime when;
  ScanEntry({required this.text, required this.when});
  Map<String,dynamic> toJson() => {'text': text, 'when': when.toIso8601String()};
  static ScanEntry fromJson(Map<String,dynamic> j) => ScanEntry(text: j['text'] as String, when: DateTime.parse(j['when'] as String));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MobileScannerController cameraController = MobileScannerController();
  List<ScanEntry> history = [];
  bool autoCopy = true;
  bool autoOpen = true;
  SharedPreferences? prefs;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.photos.request();
  }

  Future<void> _loadPrefs() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      autoCopy = prefs?.getBool('autoCopy') ?? true;
      autoOpen = prefs?.getBool('autoOpen') ?? true;
      final raw = prefs?.getStringList('history') ?? [];
      history = raw.map((s) => ScanEntry.fromJson(jsonDecode(s))).toList();
    });
  }

  Future<void> _savePrefs() async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs!.setBool('autoCopy', autoCopy);
    await prefs!.setBool('autoOpen', autoOpen);
    final raw = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs!.setStringList('history', raw);
  }

  void _handleScanResult(String data) async {
    if (isProcessing) return;
    isProcessing = true;
    try {
      final entry = ScanEntry(text: data, when: DateTime.now());
      setState(() => history.insert(0, entry));
      await _savePrefs();

      if (autoCopy) {
        await Clipboard.setData(ClipboardData(text: data));
        Fluttertoast.showToast(msg: 'Copied to clipboard');
      }

      if (autoOpen && _isProbablyUrl(data)) {
        final uri = Uri.parse(data);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (mounted) {
        showModalBottomSheet(
            context: context,
            builder: (_) => _buildResultSheet(data),
            isScrollControlled: true);
      }
    } catch (e) {
      if (kDebugMode) print('Scan handling error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      isProcessing = false;
    }
  }

  Widget _buildResultSheet(String data) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Wrap(children: [
        ListTile(
            title: const Text('Result'),
            subtitle: Text(data, style: const TextStyle(fontWeight: FontWeight.w600))),
        ButtonBar(
          alignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: data));
                  Navigator.pop(context);
                  Fluttertoast.showToast(msg: 'Copied');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy')),
            TextButton.icon(
                onPressed: () {
                  _shareText(data);
                },
                icon: const Icon(Icons.share),
                label: const Text('Share')),
            TextButton.icon(
                onPressed: () async {
                  if (_isProbablyUrl(data)) {
                    final uri = Uri.parse(data);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      Fluttertoast.showToast(msg: 'Cannot open URL');
                    }
                  } else {
                    Fluttertoast.showToast(msg: 'Not a URL');
                  }
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open')),
          ],
        ),
        const SizedBox(height: 12)
      ]),
    );
  }

  bool _isProbablyUrl(String s) {
    return s.startsWith('http://') || s.startsWith('https://') || s.startsWith('www.') || (Uri.tryParse(s)?.hasAbsolutePath == true && (s.contains('.') || s.contains('/')));
  }

  Future<void> _scanFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final input = InputImage.fromFilePath(file.path);
      final scanner = BarcodeScanner();
      final barcodes = await scanner.processImage(input);
      await scanner.close();
      if (barcodes.isEmpty) {
        Fluttertoast.showToast(msg: 'No QR/Barcode found in image');
        return;
      }
      final raw = barcodes.first.rawValue ?? '';
      _handleScanResult(raw);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error scanning image');
      if (kDebugMode) print('Gallery scan error: $e');
    }
  }

  void _shareText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(msg: 'Text copied. Paste to share.');
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF0A74FF);
    return Scaffold(
      appBar: AppBar(
        title: const Text('qr pro scanner'),
        actions: [
          IconButton(
              onPressed: () async {
                setState(() {});
              },
              icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: () {
                _showSettings();
              },
              icon: const Icon(Icons.settings)),
        ],
      ),
      body: Column(children: [
        Expanded(
          flex: 6,
          child: Stack(children: [
            MobileScanner(
              controller: cameraController,
              allowDuplicates: false,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final raw = barcodes.first.rawValue ?? '';
                  _handleScanResult(raw);
                }
              },
            ),
            Positioned(
              bottom: 18,
              right: 18,
              child: FloatingActionButton(
                  heroTag: 'torch',
                  onPressed: () async {
                    await cameraController.toggleTorch();
                    setState(() {});
                  },
                  child: ValueListenableBuilder<bool>(
                    valueListenable: cameraController.torchState,
                    builder: (context, state, child) {
                      return Icon(state ? Icons.flashlight_on : Icons.flashlight_off);
                    },
                  )),
            ),
            Positioned(
              bottom: 18,
              left: 18,
              child: FloatingActionButton.extended(
                  heroTag: 'gallery',
                  onPressed: _scanFromGallery,
                  label: const Text('Scan from gallery'),
                  icon: const Icon(Icons.photo)),
            ),
          ]),
        ),
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Settings', style: TextStyle(color: primary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Auto copy to clipboard'),
                Switch(value: autoCopy, onChanged: (v) { setState(() => autoCopy = v); _savePrefs(); })
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Auto open URLs'),
                Switch(value: autoOpen, onChanged: (v) { setState(() => autoOpen = v); _savePrefs(); })
              ]),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('History', style: TextStyle(fontWeight: FontWeight.w700)),
                TextButton(onPressed: () async { setState(() { history.clear(); }); await _savePrefs(); }, child: const Text('Clear')),
              ]),
              const SizedBox(height: 8),
              Expanded(child: _buildHistoryList()),
            ]),
          ),
        )
      ]),
    );
  }

  Widget _buildHistoryList() {
    if (history.isEmpty) return const Center(child: Text('No scans yet'));
    return ListView.separated(
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final e = history[idx];
        return ListTile(
          title: Text(e.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${e.when.toLocal()}'),
          trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: e.text)); Fluttertoast.showToast(msg: 'Copied'); }),
          onTap: () async {
            if (autoOpen && _isProbablyUrl(e.text)) {
              final uri = Uri.parse(e.text);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                Fluttertoast.showToast(msg: 'Cannot open URL');
              }
            } else {
              showModalBottomSheet(context: context, builder: (_) => _buildResultSheet(e.text));
            }
          },
        );
      },
    );
  }

  void _showSettings() {
    showDialog(context: context, builder: (c) {
      return AlertDialog(
        title: const Text('App info & settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: const [
          Text('Version 1.0'),
          SizedBox(height:8),
          Text('Scans are stored locally. No data leaves your device.')
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      );
    });
  }
}
