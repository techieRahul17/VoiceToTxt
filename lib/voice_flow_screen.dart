import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:voicetotxtvsr/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Models ---

enum ItemType { reminder, todo, note }

class SavedItem {
  final String id;
  final String text;
  final ItemType type;
  final String category;
  final DateTime timestamp;
  final DateTime? deadline;
  final String? audioPath;
  bool isCompleted;

  SavedItem({
    required this.id,
    required this.text,
    required this.type,
    required this.category,
    required this.timestamp,
    this.deadline,
    this.audioPath,
    this.isCompleted = false,
  });
}

// --- Main Screen ---

class VoiceFlowScreen extends StatefulWidget {
  const VoiceFlowScreen({super.key});

  @override
  State<VoiceFlowScreen> createState() => _VoiceFlowScreenState();
}

class _VoiceFlowScreenState extends State<VoiceFlowScreen> with TickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _currentText = "";
  final List<SavedItem> _savedItems = [];
  final TextEditingController _manualInputController = TextEditingController();
  final List<String> _userCategories = ["General", "Skills", "College", "Work", "Personal"];

  final TextEditingController _newCategoryController = TextEditingController();
  String? _customAudioPath;
  
  // Animation controllers/effects are handled via flutter_animate, 
  // but we keep a simple one for the mic pulse if needed, 
  // though flutter_animate's loop is easier.

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadCustomAudio();
    NotificationService().init();
    NotificationService().requestPermissions();
  }

  Future<void> _loadCustomAudio() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customAudioPath = prefs.getString('custom_audio_path');
    });
  }

  Future<void> _pickNotificationSound() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (result != null) {
        String path = result.files.single.path!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_audio_path', path);
        setState(() {
          _customAudioPath = path;
        });
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Reminder sound set: ${result.files.single.name}")),
           );
        }
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  @override
  void dispose() {
    _manualInputController.dispose();
    super.dispose();
  }

  void _initSpeech() async {
    await _speech.initialize(
      onError: (error) => debugPrint("Speech Error: $error"),
      onStatus: (status) {
        if (status == 'notListening' && _isListening) {
             // Optional: auto-stop logic if needed
        }
      },
    );
  }

  void _startListening() async {
    if (!_speech.isAvailable) {
      await _speech.initialize();
    }

    if (_speech.isAvailable) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() {
            _currentText = result.recognizedWords;
            if (result.finalResult) {
              _saveReceivedText(_currentText);
              _stopListening();
            }
          });
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      );
    } else {
        debugPrint("Speech recognition unavailable.");
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _currentText = ""; 
    });
  }

  void _saveReceivedText(String text, {ItemType? manualType, String? manualCategory, DateTime? manualDeadline}) {
    if (text.trim().isEmpty) return;

    final type = manualType ?? _detectIntent(text);
    final category = manualCategory ?? "General";

    final newItem = SavedItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      type: type,
      category: category,
      timestamp: DateTime.now(),
      deadline: manualDeadline,
      audioPath: null, // Basic add for now, will update manual save next
    );
    
    if (manualDeadline != null) {
      NotificationService().scheduleNotification(
        id: newItem.id.hashCode,
        title: "Reminder: ${newItem.category}",
        body: newItem.text,
        scheduledDate: manualDeadline,
        audioPath: _customAudioPath,
      );
    }

    setState(() {
      _savedItems.add(newItem); // Add to end, then sort
      _sortItems();
      _currentText = "";
    });
    
    // Simulate storage
    debugPrint("Saved: ${newItem.text} in ${newItem.category}");
  }

  ItemType _detectIntent(String text) {
    final lower = text.toLowerCase();
    if (lower.contains("remind") || lower.contains("remember")) return ItemType.reminder;
    if (lower.contains("todo") || lower.contains("task") || lower.contains("buy") || lower.contains("fix")) return ItemType.todo;
    return ItemType.note;
  }

  void _deleteItem(String id) {
    NotificationService().cancelNotification(id.hashCode);
    setState(() {
      _savedItems.removeWhere((item) => item.id == id);
    });
  }

  void _toggleItemCompletion(String id) {
    setState(() {
      final index = _savedItems.indexWhere((item) => item.id == id);
      if (index != -1) {
        _savedItems[index].isCompleted = !_savedItems[index].isCompleted;
        _sortItems();
      }
    });
  }

  void _sortItems() {
    _savedItems.sort((a, b) {
      // 1. Completed items at the bottom
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;

      // 2. Items with deadlines come first (if both not completed)
      if (a.deadline != null && b.deadline == null) return -1;
      if (a.deadline == null && b.deadline != null) return 1;

      // 3. Sort by deadline (earliest first)
      if (a.deadline != null && b.deadline != null) {
        return a.deadline!.compareTo(b.deadline!);
      }

      // 4. Default: Newest created first
      return b.timestamp.compareTo(a.timestamp);
    });
  }

  void _showManualInputModal() {
    ItemType selectedType = ItemType.note;
    String selectedCategory = _userCategories.first;
    bool isAddingNewCategory = false;
    DateTime? selectedDeadline;
    
    _manualInputController.clear();
    _newCategoryController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  top: 20,
                  left: 20,
                  right: 20,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E).withOpacity(0.9),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("New Entry", style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _manualInputController,
                      autofocus: true,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: "What's on your mind?",
                        hintStyle: GoogleFonts.outfit(color: Colors.white38),
                        border: InputBorder.none,
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                    const SizedBox(height: 20),
                    // Type Selection
                    Text("Type", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTypeChip(
                            isSelected: selectedType == ItemType.note,
                            label: "Note",
                            color: Colors.blueAccent,
                            onTap: () => setModalState(() => selectedType = ItemType.note),
                          ),
                          const SizedBox(width: 10),
                          _buildTypeChip(
                            isSelected: selectedType == ItemType.todo,
                            label: "Todo",
                            color: Colors.greenAccent,
                            onTap: () => setModalState(() => selectedType = ItemType.todo),
                          ),
                          const SizedBox(width: 10),
                          _buildTypeChip(
                            isSelected: selectedType == ItemType.reminder,
                            label: "Reminder",
                            color: Colors.purpleAccent,
                            onTap: () => setModalState(() => selectedType = ItemType.reminder),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Category Selection
                    Text("Category", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    if (isAddingNewCategory)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newCategoryController,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "Enter new category name",
                                hintStyle: GoogleFonts.outfit(color: Colors.white38),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white24)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.blueAccent)),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.greenAccent),
                            onPressed: () {
                              if (_newCategoryController.text.trim().isNotEmpty) {
                                setState(() {
                                  _userCategories.add(_newCategoryController.text.trim());
                                  selectedCategory = _newCategoryController.text.trim();
                                });
                                setModalState(() {
                                  isAddingNewCategory = false;
                                });
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.redAccent),
                            onPressed: () => setModalState(() => isAddingNewCategory = false),
                          ),
                        ],
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ..._userCategories.map((cat) => Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: _buildCategoryChip(
                                isSelected: selectedCategory == cat,
                                label: cat,
                                onTap: () => setModalState(() => selectedCategory = cat),
                              ),
                            )),
                            GestureDetector(
                              onTap: () => setModalState(() => isAddingNewCategory = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.add, size: 16, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text("Add", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        ),
                    
                    const SizedBox(height: 20),
                    
                    // Deadline Picker
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Deadline", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2100),
                              builder: (context, child) {
                                return Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Color(0xFF6366F1),
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E1E1E),
                                      onSurface: Colors.white,
                                    ),
                                    dialogBackgroundColor: const Color(0xFF1E1E1E),
                                  ),
                                  child: child!,
                                );
                              }
                            );
                            
                            if (date != null) {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                                builder: (context, child) {
                                   return Theme(
                                     data: ThemeData.dark().copyWith(
                                       colorScheme: const ColorScheme.dark(
                                         primary: Color(0xFF6366F1),
                                         onPrimary: Colors.white,
                                         surface: Color(0xFF1E1E1E),
                                         onSurface: Colors.white,
                                       ),
                                     ),
                                     child: child!,
                                   );
                                }
                              );
                              
                              if (time != null) {
                                setModalState(() {
                                  selectedDeadline = DateTime(
                                    date.year, date.month, date.day, time.hour, time.minute
                                  );
                                });
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedDeadline != null ? const Color(0xFF6366F1).withOpacity(0.2) : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: selectedDeadline != null ? const Color(0xFF6366F1) : Colors.white24),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: selectedDeadline != null ? const Color(0xFF6366F1) : Colors.white60),
                                const SizedBox(width: 8),
                                Text(
                                  selectedDeadline != null 
                                    ? DateFormat('MMM d, h:mm a').format(selectedDeadline!)
                                    : "Set Date & Time",
                                  style: GoogleFonts.outfit(
                                    color: selectedDeadline != null ? const Color(0xFF6366F1) : Colors.white60,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          _saveReceivedText(
                            _manualInputController.text, 
                            manualType: selectedType, 
                            manualCategory: selectedCategory,
                            manualDeadline: selectedDeadline
                          );
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Text("Save", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTypeChip({
    required bool isSelected,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          border: Border.all(color: isSelected ? color : Colors.transparent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? color : Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ).animate(target: isSelected ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
    );
  }

  Widget _buildCategoryChip({
    required bool isSelected,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          border: Border.all(color: isSelected ? Colors.white70 : Colors.transparent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
  
  // Correction for the chip logic above:
  // Since `selectedCategory` needs to be updated, we can just do:



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505), // Ultra dark
      body: Stack(
        children: [
          // --- Ambient Background Animation ---
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [const Color(0xFF6366F1).withOpacity(0.3), Colors.transparent]),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 4.seconds),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [const Color(0xFFEC4899).withOpacity(0.2), Colors.transparent]),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: 0, end: 50, duration: 5.seconds),
          ),
          
          // --- Main Content ---
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "VoiceFlow",
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      // Settings or Profile placeholder
                      GestureDetector(
                        onTap: _pickNotificationSound,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                          child: const Icon(Icons.music_note, color: Colors.white70),
                        ),
                      )
                    ],
                  ),
                ),

                // Transcription/Input Area
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassContainer(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 140),
                      child: Center(
                        child: _currentText.isEmpty && !_isListening
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.graphic_eq, color: Colors.white24, size: 40).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds, delay: 1.seconds),
                                  const SizedBox(height: 10),
                                  Text("Tap mic to speak\nor use + for manual", style: GoogleFonts.outfit(color: Colors.white38)),
                                ],
                              )
                            : Text(
                                _isListening && _currentText.isEmpty ? "Listening..." : _currentText,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w300,
                                ),
                              ).animate().fadeIn(),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 25),


                const SizedBox(height: 15),

                // List
                Expanded(
                  child: _savedItems.isEmpty
                      ? Center(child: Text("No items yet.", style: GoogleFonts.outfit(color: Colors.white24)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 80), // Added bottom padding for FAB
                          physics: const BouncingScrollPhysics(),
                          itemCount: _userCategories.length,
                          itemBuilder: (context, catIndex) {
                            final category = _userCategories[catIndex];
                            final itemsInCategory = _savedItems.where((item) => item.category == category).toList();
                            
                            if (itemsInCategory.isEmpty) return const SizedBox.shrink();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4, 
                                        height: 14, 
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1), 
                                          borderRadius: BorderRadius.circular(2)
                                        )
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        category.toUpperCase(),
                                        style: GoogleFonts.outfit(
                                          color: Colors.white54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...itemsInCategory.map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Dismissible(
                                      key: Key(item.id),
                                      direction: DismissDirection.endToStart,
                                      onDismissed: (_) => _deleteItem(item.id),
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(right: 20),
                                        decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                                        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      ),
                                      child: SavedItemCard(
                                        item: item,
                                        onTap: () => _toggleItemCompletion(item.id),
                                      ),
                                    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0),
                                  );
                                }),
                                const SizedBox(height: 10),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          
          // --- FABs ---
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Manual Input Button
                FloatingActionButton(
                  heroTag: "manual",
                  onPressed: _showManualInputModal,
                  backgroundColor: const Color(0xFF2C2C2E),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.keyboard, color: Colors.white70),
                ),
                
                const SizedBox(width: 20),

                // Voice Input Button (Main)
                GestureDetector(
                  onTap: _isListening ? _stopListening : _startListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isListening 
                        ? const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFEC4899)])
                        : const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF6366F1)]),
                      boxShadow: [
                         BoxShadow(
                           color: _isListening ? const Color(0xFFF43F5E).withOpacity(0.5) : const Color(0xFF3B82F6).withOpacity(0.5),
                           blurRadius: 20,
                           spreadRadius: 2
                         )
                      ],
                    ),
                    child: Icon(
                      _isListening ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ).animate(target: _isListening ? 1 : 0)
                 .scaleXY(end: 1.1, curve: Curves.easeInOut)
                 .animate(onPlay: (c) => c.repeat(reverse: true))
                 .shimmer(delay: 500.ms, duration: 1500.ms), // Pulse effect
                 
                 const SizedBox(width: 76), // Balance the row (56 + 20)
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Reusable Widgets ---

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const GlassContainer({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SavedItemCard extends StatelessWidget {
  final SavedItem item;
  final VoidCallback onTap;

  const SavedItemCard({super.key, required this.item, required this.onTap});

  Color _getColor() {
    if (item.isCompleted) return Colors.grey;
    if (_isUrgent()) return const Color(0xFFFF453A); // Urgent Red
    
    switch (item.type) {
      case ItemType.reminder: return const Color(0xFFA855F7); // Purple
      case ItemType.todo: return const Color(0xFF22D3EE); // Cyan
      case ItemType.note: return const Color(0xFFF472B6); // Pink
    }
  }

  bool _isUrgent() {
     if (item.deadline == null || item.isCompleted) return false;
     final diff = item.deadline!.difference(DateTime.now());
     return diff.inHours < 24 && !diff.isNegative;
  }

  IconData _getIcon() {
    if (item.isCompleted) return Icons.check_circle;
    switch (item.type) {
      case ItemType.reminder: return Icons.alarm;
      case ItemType.todo: return Icons.check_circle_outline;
      case ItemType.note: return Icons.sticky_note_2_outlined;
    }
  }

  String _getDeadlineText() {
    if (item.deadline == null) return "";
    final now = DateTime.now();
    final diff = item.deadline!.difference(now);

    if (diff.isNegative) return "Overdue";
    if (diff.inMinutes < 60) return "Due in ${diff.inMinutes}m";
    if (diff.inHours < 24) return "Due in ${diff.inHours}h";
    if (diff.inDays < 7) return "Due in ${diff.inDays}d";
    return DateFormat('MMM d').format(item.deadline!);
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final isUrgent = _isUrgent();
    final deadlineText = _getDeadlineText();
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 300.ms,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
           borderRadius: BorderRadius.circular(24),
           gradient: isUrgent 
             ? LinearGradient(
                 colors: [color.withOpacity(0.15), Colors.transparent], 
                 begin: Alignment.topLeft, 
                 end: Alignment.bottomRight
               )
             : null,
           boxShadow: isUrgent ? [
             BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, spreadRadius: -2)
           ] : [],
           border: isUrgent ? Border.all(color: color.withOpacity(0.3)) : null,
        ),
        child: GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              AnimatedContainer(
                duration: 300.ms,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: item.isCompleted ? Colors.white10 : color.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: item.isCompleted ? Colors.white12 : color.withOpacity(0.5), 
                    width: 1.5
                  ),
                ),
                child: Icon(_getIcon(), color: item.isCompleted ? Colors.white38 : color, size: 20),
              ),
              
              const SizedBox(width: 16),
              
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.text,
                      style: GoogleFonts.outfit(
                        color: Colors.white.withOpacity(item.isCompleted ? 0.4 : 0.95),
                        fontSize: 16,
                        fontWeight: item.isCompleted ? FontWeight.normal : FontWeight.w500,
                        decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          "${item.type.name.toUpperCase()} • ${DateFormat('h:mm a').format(item.timestamp)}",
                          style: GoogleFonts.outfit(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        if (deadlineText.isNotEmpty && !item.isCompleted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isUrgent ? color.withOpacity(0.2) : Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              deadlineText,
                              style: GoogleFonts.outfit(
                                color: isUrgent ? color : Colors.white60,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

