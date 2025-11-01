import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF7A00);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Clipboard',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: orange, brightness: Brightness.light)
            .copyWith(primary: orange),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: orange,
            side: const BorderSide(color: orange, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class ClipItem {
  ClipItem({required this.id, required this.text});
  final String id;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
  static ClipItem fromJson(Map<String, dynamic> json) =>
      ClipItem(id: json['id'] as String, text: json['text'] as String? ?? '');
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _storageKey = 'my_clipboard_items_v1';
  static const orange = Color(0xFFFF7A00);

  final List<ClipItem> _items = <ClipItem>[];
  final Set<String> _copied = <String>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(ClipItem.fromJson)
          .toList(growable: true);
      setState(() {
        _items
          ..clear()
          ..addAll(list);
      });
    } catch (_) {
      // ignore invalid data
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }

  Future<void> _openEditor({int? index}) async {
    final isEdit = index != null && index >= 0 && index < _items.length;
    final controller = TextEditingController(text: isEdit ? _items[index!].text : '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit text' : 'Add text'),
          content: SizedBox(
            width: 800,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Enter text...'
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trimRight()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return; // cancel or empty
    setState(() {
      if (isEdit) {
        _items[index!] = ClipItem(id: _items[index].id, text: result);
      } else {
        _items.insert(0, ClipItem(id: _genId(), text: result));
      }
    });
    await _persist();
  }

  String _genId() => DateTime.now().millisecondsSinceEpoch.toString() +
      '_' + (UniqueKey().hashCode & 0xFFFFFF).toRadixString(16);

  Future<void> _copy(ClipItem item) async {
    await Clipboard.setData(ClipboardData(text: item.text));
    setState(() {
      _copied.add(item.id);
    });
    _timers[item.id]?.cancel();
    _timers[item.id] = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _copied.remove(item.id);
      });
    });
  }

  void _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _items.isEmpty
                  ? const SizedBox.shrink()
                  : ReorderableListView.builder(
                      padding: EdgeInsets.zero,
                      buildDefaultDragHandles: false,
                      onReorder: _onReorder,
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _ItemRow(
                          key: ValueKey(item.id),
                          item: item,
                          onEdit: () => _openEditor(index: index),
                          onCopy: () => _copy(item),
                          dragHandleBuilder: (child) => ReorderableDragStartListener(
                            index: index,
                            child: child,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _openEditor(),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onCopy,
    required this.dragHandleBuilder,
  });

  final ClipItem item;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final Widget Function(Widget child) dragHandleBuilder;

  static const orange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    final isCopied = (context.findAncestorStateOfType<_HomePageState>()?._copied.contains(item.id) ?? false);
    final textArea = InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF1F1F1)),
        ),
        child: Text(
          item.text,
          style: const TextStyle(fontSize: 14, color: Color(0xFF222222)),
        ),
      ),
    );

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: dragHandleBuilder(
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: textArea,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: onCopy,
                  child: Text(isCopied ? 'Copied' : 'Copy'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 2, color: orange),
      ],
    );
  }
}

