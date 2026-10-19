import 'dart:convert';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotoFlowApp());
}

class PhotoFlowApp extends StatelessWidget {
  const PhotoFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7566F6);
    return MaterialApp(
      title: 'PhotoFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        fontFamily: 'Segoe UI',
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F7FB), elevation: 0),
              ),
      home: const GalleryPage(),
    );
  }
}

class PhotoItem {
  const PhotoItem({required this.path, required this.name, required this.addedAt});
  final String path;
  final String name;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {'path': path, 'name': name, 'addedAt': addedAt.toIso8601String()};
  factory PhotoItem.fromJson(Map<String, dynamic> json) => PhotoItem(
    path: json['path'] as String,
    name: json['name'] as String,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class PhotoLibrary {
  Directory? _root;
  File? _index;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'PhotoFlow', 'originals'));
    await _root!.create(recursive: true);
    _index = File(p.join(_root!.parent.path, 'library.json'));
  }

  Future<List<PhotoItem>> load() async {
    await init();
    if (!await _index!.exists()) return [];
    try {
      final decoded = jsonDecode(await _index!.readAsString()) as List<dynamic>;
      return decoded.map((e) => PhotoItem.fromJson(Map<String, dynamic>.from(e as Map))).where((e) => File(e.path).existsSync()).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } catch (_) {
      return [];
    }
  }

  Future<List<PhotoItem>> importPhotos(List<PlatformFile> selected) async {
    await init();
    final current = await load();
    final added = <PhotoItem>[];
    for (final item in selected) {
      final sourcePath = item.path;
      if (sourcePath == null) continue;
      final source = File(sourcePath);
      if (!await source.exists()) continue;
      final ext = p.extension(item.name);
      final safeExt = ext.isEmpty ? '.img' : ext;
      final target = File(p.join(_root!.path, '${DateTime.now().microsecondsSinceEpoch}_${added.length}$safeExt'));
      // Copy the original bytes directly. Do not decode or re-encode the image.
      await source.copy(target.path);
      added.add(PhotoItem(path: target.path, name: item.name, addedAt: DateTime.now()));
    }
    final all = [...added, ...current];
    await _index!.writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()), flush: true);
    return all;
  }

  Future<List<PhotoItem>> remove(PhotoItem item) async {
    final current = await load();
    final next = current.where((e) => e.path != item.path).toList();
    final file = File(item.path);
    if (await file.exists()) await file.delete();
    await _index!.writeAsString(jsonEncode(next.map((e) => e.toJson()).toList()), flush: true);
    return next;
  }
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final PhotoLibrary _library = PhotoLibrary();
  List<PhotoItem> _photos = [];
  bool _loading = true;
  bool _importing = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await _library.load();
    if (!mounted) return;
    setState(() { _photos = photos; _loading = false; });
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: false,
        dialogTitle: 'Choose photos to add to PhotoFlow',
      );
      if (result != null && result.files.isNotEmpty) {
        final photos = await _library.importPhotos(result.files);
        if (mounted) {
          setState(() => _photos = photos);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${result.files.length} photo(s) added')));
        }
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not import photos: $error')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _share(PhotoItem photo, Rect? origin) async {
    try {
      await Share.shareXFiles(
        [XFile(photo.path, mimeType: _mimeType(photo.path))],
        subject: photo.name,
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sharing failed: $error')));
    }
  }

  String _mimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.webp': return 'image/webp';
      case '.gif': return 'image/gif';
      case '.heic': return 'image/heic';
      default: return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _photos.where((photo) => photo.name.toLowerCase().contains(_filter.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.burst_mode_rounded, color: Colors.white)),
          const SizedBox(width: 12),
          const Text('PhotoFlow', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        ]),
        actions: [
          IconButton(tooltip: 'About PhotoFlow', onPressed: () => showAboutDialog(context: context, applicationName: 'PhotoFlow', applicationVersion: '0.1.0', children: const [Text('A local-first photo library. Your imported originals stay on this device.')]), icon: const Icon(Icons.info_outline_rounded)),
          const SizedBox(width: 10),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_importing ? 'Adding…' : 'Add photos'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your moments,\nyour space.', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.05)),
            const SizedBox(height: 10),
            Text('A private photo library that stays on this device.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
            const SizedBox(height: 22),
            TextField(
              onChanged: (value) => setState(() => _filter = value),
              decoration: InputDecoration(
                hintText: 'Search photo names',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Text('Library', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(20)), child: Text('${_photos.length}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 12),
            Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
                ? _EmptyLibrary(hasPhotos: _photos.isNotEmpty, onAdd: _import)
                : LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1050 ? 5 : constraints.maxWidth >= 760 ? 4 : constraints.maxWidth >= 480 ? 3 : 2;
                    return GridView.builder(
                      key: const PageStorageKey('photo-grid'),
                      itemCount: shown.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.83),
                      itemBuilder: (context, index) {
                        final photo = shown[index];
                        return OpenContainer(
                          key: ValueKey(photo.path),
                          transitionDuration: const Duration(milliseconds: 480),
                          closedElevation: 0,
                          openElevation: 0,
                          closedColor: Colors.white,
                          openColor: const Color(0xFFF7F7FB),
                          closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          openBuilder: (context, closeContainer) => PhotoViewer(photo: photo, onShare: (rect) => _share(photo, rect), onDelete: () async {
                            final next = await _library.remove(photo);
                            if (mounted) setState(() => _photos = next);
                            closeContainer();
                          }),
                          closedBuilder: (context, openContainer) => InkWell(
                            onTap: openContainer,
                            borderRadius: BorderRadius.circular(20),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(child: Hero(
                                tag: photo.path,
                                child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(File(photo.path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE7E5F5), child: Icon(Icons.broken_image_outlined, size: 34))),
                              )),
                              Padding(padding: const EdgeInsets.fromLTRB(11, 10, 11, 11), child: Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                            ]),
                          ),
                        );
                      },
                    );
                  }),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.hasPhotos, required this.onAdd});
  final bool hasPhotos;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 100, height: 100, decoration: BoxDecoration(color: const Color(0xFFEDEAFF), borderRadius: BorderRadius.circular(32)), child: const Icon(Icons.photo_library_outlined, size: 48, color: Color(0xFF7566F6))),
      const SizedBox(height: 22),
      Text(hasPhotos ? 'No matching photos' : 'Your gallery starts here', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(hasPhotos ? 'Try another search.' : 'Bring in your favorite photos. Original files are copied without image re-encoding.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.5)),
      if (!hasPhotos) ...[const SizedBox(height: 18), FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Choose photos'))],
    ]),
  ));
}

class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.photo, required this.onShare, required this.onDelete});
  final PhotoItem photo;
  final Future<void> Function(Rect? origin) onShare;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded)),
      title: Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        IconButton(tooltip: 'Share original', onPressed: () => onShare(null), icon: const Icon(Icons.ios_share_rounded)),
        IconButton(tooltip: 'Remove from library', onPressed: () async {
          final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
            title: const Text('Delete this photo?'),
            content: const Text('This removes the copied original from PhotoFlow on this device.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
          ));
          if (confirmed == true) await onDelete();
        }, icon: const Icon(Icons.delete_outline_rounded)),
        const SizedBox(width: 8),
      ],
    ),
    body: Center(child: Padding(padding: const EdgeInsets.all(16), child: Hero(tag: photo.path, child: InteractiveViewer(minScale: 0.5, maxScale: 5, child: Image.file(File(photo.path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 64)))))),
    bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Row(children: [
      const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.black54),
      const SizedBox(width: 8),
      const Expanded(child: Text('Stored locally • Original file', style: TextStyle(color: Colors.black54))),
      FilledButton.icon(onPressed: () => onShare(null), icon: const Icon(Icons.share_rounded), label: const Text('Share')),
    ]))),
  );
}
