// Pocket Notes - Plants
// Stores plants (plant name, watering notes) in sqflite and the theme choice
// in SharedPreferencesAsync, so both survive a force-kill.
 
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
 
// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Plant {
  final int? id; // null until the database assigns an auto-increment id
  final String plantName;
  final String wateringNotes;
 
  const Plant({this.id, required this.plantName, required this.wateringNotes});
 
  // id is left out when null so SQLite auto-increments it on insert.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'plant_name': plantName,
        'watering_notes': wateringNotes,
      };
 
  factory Plant.fromMap(Map<String, Object?> map) => Plant(
        id: map['id'] as int,
        plantName: map['plant_name'] as String,
        wateringNotes: map['watering_notes'] as String,
      );
}
 
// ---------------------------------------------------------------------------
// Database: opened ONCE, and that single instance is reused everywhere.
// We cache the Future (not just the Database), so even if two callers ask at
// the same moment, _open() only runs one time.
// ---------------------------------------------------------------------------
class AppDatabase {
  AppDatabase._(); // private constructor: nobody else can create another one
  static final AppDatabase instance = AppDatabase._();
 
  static const String table = 'plants';
  Future<Database>? _dbFuture;
 
  Future<Database> get database => _dbFuture ??= _open();
 
  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'pocket_notes.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          plant_name TEXT NOT NULL,
          watering_notes TEXT NOT NULL
        )
      '''),
    );
  }
 
  Future<List<Plant>> getPlants() async {
    final db = await database;
    final rows = await db.query(table, orderBy: 'id ASC');
    // Database proof (Part 3, #7): shows the raw rows in the console.
    debugPrint('DB ROWS: $rows');
    return rows.map(Plant.fromMap).toList();
  }
 
  Future<int> insertPlant(Plant plant) async {
    final db = await database;
    return db.insert(table, plant.toMap());
  }
 
  // where + whereArgs: the ? is filled in safely by sqflite (no string-gluing).
  Future<int> updatePlant(Plant plant) async {
    final db = await database;
    return db.update(
      table,
      plant.toMap(),
      where: 'id = ?',
      whereArgs: [plant.id],
    );
  }
 
  Future<int> deletePlant(int id) async {
    final db = await database;
    return db.delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
 
// ---------------------------------------------------------------------------
// Startup: read the saved theme BEFORE runApp so the first frame is correct.
// ---------------------------------------------------------------------------
const String _themeKey = 'isDark';
 
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = SharedPreferencesAsync();
  final isDark = await prefs.getBool(_themeKey) ?? false;
  runApp(PocketNotesApp(initialDark: isDark));
}
 
class PocketNotesApp extends StatefulWidget {
  final bool initialDark;
  const PocketNotesApp({super.key, required this.initialDark});
 
  @override
  State<PocketNotesApp> createState() => _PocketNotesAppState();
}
 
class _PocketNotesAppState extends State<PocketNotesApp> {
  late bool _isDark = widget.initialDark;
 
  Future<void> _setDark(bool value) async {
    setState(() => _isDark = value);
    // Save the choice so it is restored on the next launch.
    await SharedPreferencesAsync().setBool(_themeKey, value);
  }
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Notes',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      home: PlantListPage(isDark: _isDark, onThemeChanged: _setDark),
    );
  }
}
 
// ---------------------------------------------------------------------------
// Main screen: list + add/edit/delete
// ---------------------------------------------------------------------------
class PlantListPage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  const PlantListPage({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
  });
 
  @override
  State<PlantListPage> createState() => _PlantListPageState();
}
 
class _PlantListPageState extends State<PlantListPage> {
  List<Plant> _plants = [];
  bool _loading = true;
 
  @override
  void initState() {
    super.initState();
    _load(); // records load from sqflite when the app launches
  }
 
  Future<void> _load() async {
    final plants = await AppDatabase.instance.getPlants();
    if (!mounted) return;
    setState(() {
      _plants = plants;
      _loading = false;
    });
  }
 
  Future<void> _addOrEdit([Plant? existing]) async {
    final result = await showDialog<Plant>(
      context: context,
      builder: (_) => _PlantDialog(existing: existing),
    );
    if (result == null) return;
 
    if (existing == null) {
      await AppDatabase.instance.insertPlant(result);
    } else {
      await AppDatabase.instance.updatePlant(result);
    }
    await _load();
  }
 
  Future<void> _delete(Plant plant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete plant?'),
        content: Text('Remove "${plant.plantName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AppDatabase.instance.deletePlant(plant.id!);
    await _load();
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Notes: Plants'),
        actions: [
          Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
          Switch(
            value: widget.isDark,
            onChanged: widget.onThemeChanged,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plants.isEmpty
              ? const Center(child: Text('No plants yet. Tap + to add one.'))
              : ListView.builder(
                  itemCount: _plants.length,
                  itemBuilder: (context, i) {
                    final plant = _plants[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${plant.id}')),
                      title: Text(plant.plantName),
                      subtitle: Text(plant.wateringNotes),
                      onTap: () => _addOrEdit(plant), // tap = edit
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(plant),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
 
// ---------------------------------------------------------------------------
// Add / edit dialog (its own widget so the controllers are disposed properly)
// ---------------------------------------------------------------------------
class _PlantDialog extends StatefulWidget {
  final Plant? existing;
  const _PlantDialog({this.existing});
 
  @override
  State<_PlantDialog> createState() => _PlantDialogState();
}
 
class _PlantDialogState extends State<_PlantDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.plantName ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.wateringNotes ?? '');
 
  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }
 
  void _save() {
    final name = _name.text.trim();
    final notes = _notes.text.trim();
    if (name.isEmpty || notes.isEmpty) return;
    Navigator.pop(
      context,
      Plant(id: widget.existing?.id, plantName: name, wateringNotes: notes),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add plant' : 'Edit plant'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Plant name'),
            textCapitalization: TextCapitalization.sentences,
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Watering notes'),
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
