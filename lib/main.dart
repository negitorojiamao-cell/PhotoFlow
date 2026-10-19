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
  const PhotoItem({
    required this.path,
    required this.name,
    required this.addedAt,
    this.tags = const [],
  });

  final String path;
  final String name;
  final DateTime addedAt;
  final List<String> tags;

  PhotoItem copyWith({List<String>? tags}) => PhotoItem(
    path: path,
    name: name,
    addedAt: addedAt,
    tags: tags ?? this.tags,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'addedAt': addedAt.toIso8601String(),
    'tags': tags,
  };

  factory PhotoItem.fromJson(Map<String, dynamic> json) => PhotoItem(
    path: json['path'] as String,
    name: json['name'] as String,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    tags: (json['tags'] as List<dynamic>? ?? const []).whereType<String>().toList(),
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
      return decoded
          .map((e) => PhotoItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((e) => File(e.path).existsSync())
          .toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<PhotoItem> photos) async {
    await _index!.writeAsString(
      jsonEncode(photos.map((e) => e.toJson()).toList()),
      flush: true,
    );
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
      final target = File(p.join(
        _root!.path,
        '${DateTime.now().microsecondsSinceEpoch}_${added.length}$safeExt',
      ));
      // Copy the original bytes directly; do not decode or re-encode images.
      await source.copy(target.path);
      added.add(PhotoItem(path: target.path, name: item.name, addedAt: DateTime.now()));
    }
    final all = [...added, ...current];
    await _save(all);
    return all;
  }

  Future<List<PhotoItem>> updateTags(List<PhotoItem> current, Set<String> paths, List<String> tags) async {
    final next = current.map((photo) => paths.contains(photo.path) ? photo.copyWith(tags: tags) : photo).toList();
    await _save(next);
    return next;
  }

  Future<List<PhotoItem>> remove(PhotoItem item) async {
    final current = await load();
    final next = current.where((e) => e.path != item.path).toList();
    final file = File(item.path);
    if (await file.exists()) await file.delete();
    await _save(next);
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
  String? _activeTag;
  final Set<String> _selectedPaths = {};

  bool get _selectionMode => _selectedPaths.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await _library.load();
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _loading = false;
    });
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${result.files.length} photo(s) added')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import photos: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toggleSelection(PhotoItem photo) {
    setState(() {
      if (!_selectedPaths.add(photo.path)) _selectedPaths.remove(photo.path);
    });
  }

  void _openPhoto(PhotoItem photo) {
    if (_selectionMode) {
      _toggleSelection(photo);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PhotoViewer(
        photo: photo,
        onShare: () => _share(photo),
        onDelete: () async {
          final next = await _library.remove(photo);
          if (mounted) setState(() => _photos = next);
          if (mounted) Navigator.of(context).pop();
        },
        onTagsChanged: (tags) async {
          final next = await _library.updateTags(_photos, {photo.path}, tags);
          if (mounted) setState(() => _photos = next);
        },
      ),
    ));
  }

  Future<void> _share(PhotoItem photo) async {
    try {
      await Share.shareXFiles(
        [XFile(photo.path, mimeType: _mimeType(photo.path))],
        subject: photo.name,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sharing failed: $error')),
        );
      }
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

  Future<void> _editSelectedTags() async {
    if (_selectedPaths.isEmpty) return;
    final selected = _photos.where((p) => _selectedPaths.contains(p.path)).toList();
    final existingTags = _photos.expand((p) => p.tags).toSet().toList()..sort();
    final commonTags = selected.isEmpty ? <String>{} : selected.first.tags.toSet();
    final controller = TextEditingController();
    final chosen = <String>{...commonTags};
    final newTag = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text('Organize ${selected.length} photo(s)'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose tags to move these photos into that collection.'),
              const SizedBox(height: 12),
              if (existingTags.isEmpty) const Text('No tags yet. Create one below.', style: TextStyle(color: Colors.black54)),
              Wrap(spacing: 8, runSpacing: 6, children: existingTags.map((tag) => FilterChip(
                label: Text(tag),
                selected: chosen.contains(tag),
                onSelected: (value) => setDialogState(() {
                  if (value) { chosen.add(tag); } else { chosen.remove(tag); }
                }),
              )).toList()),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Create a new tag',
                  hintText: 'e.g. Travel, Friends, Favorites',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) => Navigator.pop(context, value.trim()),
              ),
              const SizedBox(height: 8),
              const Text('Tags can overlap: one photo can belong to several collections.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Apply selected tags')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create & apply')),
        ],
      )),
    );
    controller.dispose();
    if (!mounted) return;
    final tags = <String>{...chosen};
    if (newTag != null && newTag.isNotEmpty) tags.add(newTag);
    if (newTag == null) return;
    // An empty string means "apply selected tags"; null means cancel.
    final next = await _library.updateTags(_photos, _selectedPaths, tags.toList()..sort());
    if (!mounted) return;
    setState(() {
      _photos = next;
      _selectedPaths.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated tags for ${selected.length} photo(s)')),
    );
  }

  Future<void> _editOnePhotoTags(PhotoItem photo) async {
    final controller = TextEditingController(text: photo.tags.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit photo tags'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tags (comma-separated)',
              hintText: 'Travel, Friends, Favorites',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save tags')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final tags = result.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final next = await _library.updateTags(_photos, {photo.path}, tags);
    if (mounted) setState(() => _photos = next);
  }

  @override
  Widget build(BuildContext context) {
    final allTags = _photos.expand((photo) => photo.tags).toSet().toList()..sort();
    final shown = _photos.where((photo) {
      final matchesName = photo.name.toLowerCase().contains(_filter.toLowerCase());
      final matchesTag = _activeTag == null || photo.tags.contains(_activeTag);
      return matchesName && matchesTag;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.burst_mode_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Text('PhotoFlow', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        ]),
        actions: [
          if (_selectionMode)
            TextButton.icon(
              onPressed: _editSelectedTags,
              icon: const Icon(Icons.drive_file_move_outline_rounded),
              label: Text('Organize (${_selectedPaths.length})'),
            ),
          if (_selectionMode)
            IconButton(tooltip: 'Select all visible', onPressed: () => setState(() => _selectedPaths.addAll(shown.map((p) => p.path))), icon: const Icon(Icons.select_all_rounded)),
          if (_selectionMode)
            IconButton(tooltip: 'Clear selection', onPressed: () => setState(_selectedPaths.clear), icon: const Icon(Icons.close_rounded)),
          IconButton(
            tooltip: 'About PhotoFlow',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'PhotoFlow',
              applicationVersion: '0.1.0',
              children: const [Text('A local-first photo library. Your imported originals stay on this device.')],
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 10),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_importing ? 'Adding…' : 'Add photos'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _selectionMode ? '${_selectedPaths.length} selected' : 'Your moments,\nyour space.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.05),
            ),
            const SizedBox(height: 10),
            Text(
              _selectionMode ? 'Double-click or long-press photos to change selection.' : 'A private photo library that stays on this device.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('All photos (${_photos.length})'),
                    selected: _activeTag == null,
                    onSelected: (_) => setState(() => _activeTag = null),
                  ),
                ),
                ...allTags.map((tag) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$tag (${_photos.where((p) => p.tags.contains(tag)).length})'),
                    selected: _activeTag == tag,
                    onSelected: (_) => setState(() => _activeTag = _activeTag == tag ? null : tag),
                  ),
                )),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text(_activeTag ?? 'Library', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                child: Text('${shown.length}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (!_selectionMode)
                TextButton.icon(onPressed: () => _editSelectedTags(), icon: const Icon(Icons.label_outline_rounded), label: const Text('Tag selected')),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
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
                              final selected = _selectedPaths.contains(photo.path);
                              return OpenContainer(
                                key: ValueKey(photo.path),
                                tappable: !_selectionMode,
                                transitionDuration: const Duration(milliseconds: 420),
                                closedElevation: 0,
                                openElevation: 0,
                                closedColor: Colors.white,
                                openColor: const Color(0xFFF7F7FB),
                                closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                openBuilder: (context, closeContainer) => PhotoViewer(
                                  photo: photo,
                                  onShare: () => _share(photo),
                                  onDelete: () async {
                                    final next = await _library.remove(photo);
                                    if (mounted) setState(() => _photos = next);
                                    closeContainer();
                                  },
                                  onTagsChanged: (tags) async {
                                    final next = await _library.updateTags(_photos, {photo.path}, tags);
                                    if (mounted) setState(() => _photos = next);
                                  },
                                ),
                                closedBuilder: (context, openContainer) => GestureDetector(
                                  onTap: () {
                                    if (_selectionMode) {
                                      _toggleSelection(photo);
                                    } else {
                                      openContainer();
                                    }
                                  },
                                  onDoubleTap: () => _toggleSelection(photo),
                                  onLongPress: () => _toggleSelection(photo),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    decoration: BoxDecoration(
                                      color: selected ? const Color(0xFFECE8FF) : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
                                      boxShadow: selected ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))] : const [],
                                    ),
                                    child: Stack(children: [
                                      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                        Expanded(
                                          child: Hero(
                                            tag: photo.path,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(18),
                                              child: Image.file(
                                                File(photo.path),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE7E5F5), child: Icon(Icons.broken_image_outlined, size: 34)),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                            if (photo.tags.isNotEmpty) ...[
                                              const SizedBox(height: 5),
                                              Wrap(spacing: 4, runSpacing: 3, children: photo.tags.take(2).map((tag) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: const Color(0xFFEDEAFF), borderRadius: BorderRadius.circular(6)),
                                                child: Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Color(0xFF5E4DD0))),
                                              )).toList()),
                                            ],
                                          ]),
                                        ),
                                      ]),
                                      if (selected)
                                        Positioned(
                                          top: 10, right: 10,
                                          child: Container(
                                            width: 28, height: 28,
                                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                                            child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                                          ),
                                        ),
                                      if (_selectionMode && !selected)
                                        const Positioned(top: 10, right: 10, child: Icon(Icons.circle_outlined, color: Colors.white, shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          );
                        }),
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
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 100, height: 100, decoration: BoxDecoration(color: const Color(0xFFEDEAFF), borderRadius: BorderRadius.circular(32)), child: const Icon(Icons.photo_library_outlined, size: 48, color: Color(0xFF7566F6))),
        const SizedBox(height: 22),
        Text(hasPhotos ? 'No matching photos' : 'Your gallery starts here', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(hasPhotos ? 'Try another search or tag.' : 'Bring in your favorite photos. Original files are copied without image re-encoding.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.5)),
        if (!hasPhotos) ...[const SizedBox(height: 18), FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Choose photos'))],
      ]),
    ),
  );
}

class PhotoViewer extends StatelessWidget {
  const PhotoViewer({
    super.key,
    required this.photo,
    required this.onShare,
    required this.onDelete,
    required this.onTagsChanged,
  });

  final PhotoItem photo;
  final Future<void> Function() onShare;
  final Future<void> Function() onDelete;
  final Future<void> Function(List<String>) onTagsChanged;

  Future<void> _editTags(BuildContext context) async {
    final controller = TextEditingController(text: photo.tags.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit photo tags'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tags (comma-separated)', hintText: 'Travel, Friends, Favorites', border: OutlineInputBorder()),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save tags')),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final tags = result.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    await onTagsChanged(tags);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded)),
      title: Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        IconButton(tooltip: 'Edit tags', onPressed: () => _editTags(context), icon: const Icon(Icons.sell_outlined)),
        IconButton(tooltip: 'Share original', onPressed: onShare, icon: const Icon(Icons.ios_share_rounded)),
        IconButton(tooltip: 'Remove from library', onPressed: () async {
          final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
            title: const Text('Delete this photo?'),
            content: const Text('This removes the copied original from PhotoFlow on this device.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ));
          if (confirmed == true) await onDelete();
        }, icon: const Icon(Icons.delete_outline_rounded)),
        const SizedBox(width: 8),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Hero(
          tag: photo.path,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.file(File(photo.path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 64)),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          const Expanded(child: Text('Stored locally • Original file', style: TextStyle(color: Colors.black54))),
          FilledButton.icon(onPressed: onShare, icon: const Icon(Icons.share_rounded), label: const Text('Share')),
        ]),
      ),
    ),
  );
}
