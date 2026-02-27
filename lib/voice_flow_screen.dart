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

class SubTaskItem {
  String text;
  bool isCompleted;
  
  SubTaskItem({required this.text, this.isCompleted = false});
}

class SubTask {
  String title;
  List<SubTaskItem> items;
  bool isExpanded;
  
  SubTask({required this.title, List<SubTaskItem>? items, this.isExpanded = true}) : items = items ?? [];
}

class SavedItem {
  final String id;
  final String text;
  final ItemType type;
  final String category;
  final DateTime timestamp;
  final DateTime? deadline;
  final String? audioPath;
  bool isCompleted;
  List<SubTask> subTasks;

  SavedItem({
    required this.id,
    required this.text,
    required this.type,
    required this.category,
    required this.timestamp,
    this.deadline,
    this.audioPath,
    this.isCompleted = false,
    List<SubTask>? subTasks,
  }) : this.subTasks = subTasks ?? [];
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

  // --- Navigation System ---
  int _currentTabIndex = 0; // 0=Tasks, 1=Notes, 2=Reminders

  // --- Pet Gamification System ---
  int _petLevel = 1;
  int _petExp = 0;
  List<OverlayEntry> _xpOverlays = [];
  
  // Animation controllers/effects are handled via flutter_animate, 
  // but we keep a simple one for the mic pulse if needed, 
  // though flutter_animate's loop is easier.

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadCustomAudio();
    _loadPetData();
    NotificationService().init();
    NotificationService().requestPermissions();
  }

  Future<void> _loadPetData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _petLevel = prefs.getInt('pet_level') ?? 1;
      _petExp = prefs.getInt('pet_exp') ?? 0;
    });
  }

  Future<void> _savePetData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pet_level', _petLevel);
    await prefs.setInt('pet_exp', _petExp);
  }

  void _addExpAndCheckLevelUp(BuildContext context) {
    setState(() {
      _petExp += 10;
      int requiredExp = _petLevel * 50;
      
      if (_petExp >= requiredExp) {
        _petExp -= requiredExp;
        _petLevel++;
        _savePetData();
        _showLevelUpOverlay(context);
        
        // Vibrate or play cheer sound?
      } else {
        _savePetData();
      }
    });
  }

  void _showLevelUpOverlay(BuildContext context) {
    if (!mounted) return;
    
    OverlayState? overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 100,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "LEVEL UP!",
                  style: GoogleFonts.outfit(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.yellowAccent,
                    shadows: [
                      Shadow(color: Colors.orangeAccent, blurRadius: 20),
                      Shadow(color: Colors.white, blurRadius: 10),
                    ]
                  ),
                ).animate()
                 .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.2, 1.2), duration: 600.ms, curve: Curves.elasticOut)
                 .fadeOut(delay: 2000.ms, duration: 500.ms),
                  
                const SizedBox(height: 10),
                
                Text(
                  "Aura Pet reached Level $_petLevel!",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ).animate()
                 .slideY(begin: 0.5, end: 0, duration: 400.ms, curve: Curves.easeOut)
                 .fadeOut(delay: 2000.ms, duration: 500.ms),
              ],
            ),
          ),
        );
      },
    );
    
    overlayState.insert(overlayEntry);
    
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  void _showFloatingXP(BuildContext context) {
    if (!mounted) return;
    
    OverlayState? overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    // Slight random offset for stacking
    final xOffset = (DateTime.now().millisecond % 40) - 20.0;
    
    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 150, // Below pet avatar
          right: 40 + xOffset, // Below pet avatar roughly
          child: Material(
            color: Colors.transparent,
            child: Text(
              "+10 XP",
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF22D3EE),
                shadows: [
                  Shadow(color: const Color(0xFF22D3EE).withOpacity(0.5), blurRadius: 10),
                ]
              ),
            ).animate()
             .slideY(begin: 0, end: -2.0, duration: 1000.ms, curve: Curves.easeOut)
             .fadeOut(delay: 500.ms, duration: 500.ms)
             .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 200.ms),
          ),
        );
      },
    );
    
    overlayState.insert(overlayEntry);
    _xpOverlays.add(overlayEntry);
    
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
        _xpOverlays.remove(overlayEntry);
      }
    });
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
    for (var overlay in _xpOverlays) {
      if (overlay.mounted) overlay.remove();
    }
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
        bool wasCompleted = _savedItems[index].isCompleted;
        _savedItems[index].isCompleted = !wasCompleted;
        
        if (!wasCompleted) {
            // Task marked as complete, give XP!
            _addExpAndCheckLevelUp(context);
            _showFloatingXP(context);
        } else {
            // Optional: Remove XP if unchecked, but for Gamification, 
            // usually better to just not give it back unless you want strict tracking.
        }
        
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
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.4), 
                    Colors.transparent
                  ],
                  radius: 0.8,
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.5, 1.5), duration: 6.seconds)
             .move(begin: const Offset(0, 0), end: const Offset(-50, 50), duration: 8.seconds),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899).withOpacity(0.35), 
                    Colors.transparent
                  ],
                  radius: 0.8,
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .move(begin: const Offset(0, 0), end: const Offset(50, -50), duration: 10.seconds)
             .scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3), duration: 7.seconds),
          ),
          Positioned(
            top: 200,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF22D3EE).withOpacity(0.2), 
                    Colors.transparent
                  ],
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .fadeIn(duration: 4.seconds)
             .moveX(begin: -50, end: 150, duration: 12.seconds),
          ),
          
          // --- Main Content ---
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // Slightly reduced padding
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "VoiceFlow",
                            style: GoogleFonts.outfit(
                              fontSize: 28, // Slighly smaller base
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ).animate().fadeIn(duration: 800.ms).slideX(begin: -0.2, end: 0, curve: Curves.easeOut),
                        ),
                      ),
                      
                      const SizedBox(width: 10),                      Row(
                        children: [
                          // Pet Avatar
                          PetAvatar(level: _petLevel, exp: _petExp),
                          
                          const SizedBox(width: 15),

                          // Settings / Custom Audio
                          GestureDetector(
                            onTap: _pickNotificationSound,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08), 
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
                            ),
                          ).animate().fadeIn(delay: 200.ms).scale(),
                        ],
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
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(5, (index) {
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        width: 4,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                                       .scaleY(begin: 1.0, end: 1.5, duration: (600 + index * 100).ms, delay: (index * 100).ms);
                                    }),
                                  ),
                                  const SizedBox(height: 15),
                                  Text("Tap mic to speak\nor use + for manual", style: GoogleFonts.outfit(color: Colors.white38)),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isListening)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(10, (index) {
                                        return Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 3),
                                          width: 4,
                                          height: 30, // Base height
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF43F5E), // Listening color
                                            borderRadius: BorderRadius.circular(2),
                                            boxShadow: [
                                              BoxShadow(color: const Color(0xFFF43F5E).withOpacity(0.5), blurRadius: 6)
                                            ]
                                          ),
                                        ).animate(onPlay: (c) => c.repeat(reverse: true))
                                         .scaleY(
                                            begin: 0.2, 
                                            end: 1.5 + (index % 3) * 0.5, // Random-ish variation
                                            duration: (300 + (index * 50)).ms
                                          );
                                      }),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                    
                                  const SizedBox(height: 10),
                                  
                                  Text(
                                    _currentText.isEmpty ? "Listening..." : _currentText,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w300,
                                      height: 1.3,
                                    ),
                                  ).animate().fadeIn(),
                                ],
                              ),
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
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 160), // Added bottom padding for FABs & Nav
                          physics: const BouncingScrollPhysics(),
                          itemCount: _userCategories.length,
                          itemBuilder: (context, catIndex) {
                            final category = _userCategories[catIndex];
                            
                            // Filter items by category AND current tab
                            final itemsInCategory = _savedItems.where((item) {
                              if (item.category != category) return false;
                              if (_currentTabIndex == 0) return item.type == ItemType.todo;
                              if (_currentTabIndex == 1) return item.type == ItemType.note;
                              if (_currentTabIndex == 2) return item.type == ItemType.reminder;
                              return false;
                            }).toList();
                            
                            if (itemsInCategory.isEmpty) return const SizedBox.shrink();

                            return CategoryFolder(
                              category: category,
                              items: itemsInCategory,
                              onToggleItem: _toggleItemCompletion,
                              onDeleteItem: _deleteItem,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          
          // --- Bottom Floating Actions ---
          Positioned(
            bottom: 90, // Raised above nav bar
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
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: Colors.white.withOpacity(0.1))
                  ),
                  child: const Icon(Icons.keyboard_rounded, color: Colors.white, size: 26),
                ).animate().scale(delay: 400.ms, curve: Curves.elasticOut),
                
                const SizedBox(width: 30),

                // Voice Input Button (Main)
                GestureDetector(
                  onTap: _isListening ? _stopListening : _startListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutBack,
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isListening 
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF43F5E), Color(0xFFFB7185)]
                          )
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF4F46E5), Color(0xFF818CF8)] // Indigo to IndigoAccent
                          ),
                      boxShadow: [
                         BoxShadow(
                           color: _isListening ? const Color(0xFFF43F5E).withOpacity(0.6) : const Color(0xFF4F46E5).withOpacity(0.6),
                           blurRadius: _isListening ? 30 : 20,
                           spreadRadius: _isListening ? 4 : 0,
                           offset: const Offset(0, 8)
                         )
                      ],
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    ),
                    child: Icon(
                      _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ).animate(target: _isListening ? 1 : 0)
                 .scaleXY(end: 1.15, curve: Curves.easeInOut)
                 .animate(onPlay: (c) => c.repeat(reverse: true))
                 .shimmer(delay: 500.ms, duration: 1500.ms, color: Colors.white54), // Pulse effect
                 
               ],
            ),
          ),
          
          // --- Aesthetic Bottom Navigation ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withOpacity(0.6),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavItem(0, Icons.check_circle_outline_rounded, "Tasks", const Color(0xFF22D3EE)),
                      _buildNavItem(1, Icons.sticky_note_2_rounded, "Notes", const Color(0xFFF472B6)),
                      _buildNavItem(2, Icons.notifications_none_rounded, "Reminders", const Color(0xFFA855F7)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, Color tintColor) {
    bool isSelected = _currentTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: 300.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tintColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: tintColor.withOpacity(0.3)) : Border.all(color: Colors.transparent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? tintColor : Colors.white54,
              size: isSelected ? 26 : 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? tintColor : Colors.white54,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
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
            color: Colors.white.withOpacity(0.03), // Reduced opacity for cleaner look
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
              width: 1.0,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SavedItemCard extends StatefulWidget {
  final SavedItem item;
  final VoidCallback onTap;

  const SavedItemCard({super.key, required this.item, required this.onTap});

  @override
  State<SavedItemCard> createState() => _SavedItemCardState();
}

class _SavedItemCardState extends State<SavedItemCard> {
  final TextEditingController _subtaskController = TextEditingController();
  final TextEditingController _subtaskItemController = TextEditingController();

  Color _getColor() {
    if (widget.item.isCompleted) return Colors.grey;
    if (_isUrgent()) return const Color(0xFFFF453A); // Urgent Red
    
    switch (widget.item.type) {
      case ItemType.reminder: return const Color(0xFFA855F7); // Purple
      case ItemType.todo: return const Color(0xFF22D3EE); // Cyan
      case ItemType.note: return const Color(0xFFF472B6); // Pink
    }
  }

  bool _isUrgent() {
     if (widget.item.deadline == null || widget.item.isCompleted) return false;
     final diff = widget.item.deadline!.difference(DateTime.now());
     return diff.inHours < 24 && !diff.isNegative;
  }

  IconData _getIcon() {
    if (widget.item.isCompleted) return Icons.check_circle;
    switch (widget.item.type) {
      case ItemType.reminder: return Icons.alarm;
      case ItemType.todo: return Icons.check_circle_outline;
      case ItemType.note: return Icons.sticky_note_2_outlined;
    }
  }

  String _getDeadlineText() {
    if (widget.item.deadline == null) return "";
    final now = DateTime.now();
    final diff = widget.item.deadline!.difference(now);

    if (diff.isNegative) return "Overdue";
    if (diff.inMinutes < 60) return "Due in ${diff.inMinutes}m";
    if (diff.inHours < 24) return "Due in ${diff.inHours}h";
    if (diff.inDays < 7) return "Due in ${diff.inDays}d";
    return DateFormat('MMM d').format(widget.item.deadline!);
  }

  void _showAddSubTaskDialog() {
    _subtaskController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text("Add Checklist", style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: _subtaskController,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: "E.g., Workout Routine",
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              if (_subtaskController.text.trim().isNotEmpty) {
                setState(() {
                  widget.item.subTasks.add(SubTask(title: _subtaskController.text.trim()));
                });
              }
              Navigator.pop(context);
            },
            child: Text("Add", style: GoogleFonts.outfit(color: const Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  void _showAddSubTaskItemDialog(SubTask subTask) {
    _subtaskItemController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text("Add Item to ${subTask.title}", style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: _subtaskItemController,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: "E.g., Bench Press",
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              if (_subtaskItemController.text.trim().isNotEmpty) {
                setState(() {
                  subTask.items.add(SubTaskItem(text: _subtaskItemController.text.trim()));
                });
              }
              Navigator.pop(context);
            },
            child: Text("Add", style: GoogleFonts.outfit(color: const Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final isUrgent = _isUrgent();
    final deadlineText = _getDeadlineText();
    
    return GestureDetector(
      onTap: widget.onTap,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  AnimatedContainer(
                    duration: 300.ms,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.item.isCompleted ? Colors.white10 : color.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.item.isCompleted ? Colors.white12 : color.withOpacity(0.5), 
                        width: 1.5
                      ),
                    ),
                    child: Icon(_getIcon(), color: widget.item.isCompleted ? Colors.white38 : color, size: 20),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Text Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.text,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(widget.item.isCompleted ? 0.4 : 0.95),
                            fontSize: 16,
                            fontWeight: widget.item.isCompleted ? FontWeight.normal : FontWeight.w500,
                            decoration: widget.item.isCompleted ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.white38,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              "${widget.item.type.name.toUpperCase()} • ${DateFormat('h:mm a').format(widget.item.timestamp)}",
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                            if (deadlineText.isNotEmpty && !widget.item.isCompleted) ...[
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
                            ],
                            const Spacer(),
                            if (!widget.item.isCompleted)
                              GestureDetector(
                                onTap: _showAddSubTaskDialog,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.add, size: 12, color: Color(0xFF818CF8)),
                                      const SizedBox(width: 2),
                                      Text("List", style: GoogleFonts.outfit(color: const Color(0xFF818CF8), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ]
                                  )
                                )
                              )
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Subtasks Rendering
              if (widget.item.subTasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(left: 44), // Align with text logic roughly
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.item.subTasks.map((subTask) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05))
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // SubTask Header
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    subTask.isExpanded = !subTask.isExpanded;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(12)
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        subTask.isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                        size: 16,
                                        color: Colors.white54
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          subTask.title,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _showAddSubTaskItemDialog(subTask),
                                        child: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF22D3EE))
                                      )
                                    ]
                                  )
                                )
                              ),
                              
                              // SubTask Items
                              if (subTask.isExpanded && subTask.items.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4, bottom: 8, left: 16, right: 12),
                                  child: Column(
                                    children: subTask.items.map((subItem) {
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            subItem.isCompleted = !subItem.isCompleted;
                                            // Ensure parent doesn't toggle
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 14,
                                                height: 14,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: subItem.isCompleted ? const Color(0xFF10B981) : Colors.white38,
                                                    width: 1.5
                                                  ),
                                                  color: subItem.isCompleted ? const Color(0xFF10B981) : Colors.transparent
                                                ),
                                                child: subItem.isCompleted 
                                                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                                                  : null,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  subItem.text,
                                                  style: GoogleFonts.outfit(
                                                    color: subItem.isCompleted ? Colors.white38 : Colors.white70,
                                                    fontSize: 12,
                                                    decoration: subItem.isCompleted ? TextDecoration.lineThrough : null,
                                                  )
                                                )
                                              )
                                            ]
                                          )
                                        )
                                      );
                                    }).toList()
                                  )
                                )
                            ]
                          )
                        )
                      );
                    }).toList()
                  )
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class PetAvatar extends StatelessWidget {
  final int level;
  final int exp;
  
  const PetAvatar({
    super.key,
    required this.level,
    required this.exp,
  });

  String _getPetEmoji() {
    if (level == 1) return "🥚"; // Egg
    if (level == 2) return "🐣"; // Hatching
    if (level == 3) return "🐥"; // Baby
    if (level == 4) return "🦅"; // Bird
    return "🐉"; // Dragon (Max)
  }

  Color _getAuraColor() {
    if (level == 1) return Colors.white;
    if (level == 2) return const Color(0xFFFDE047); // Yellow
    if (level == 3) return const Color(0xFFFCD34D); // Amber
    if (level == 4) return const Color(0xFF60A5FA); // Blue
    return const Color(0xFFA855F7); // Purple
  }

  String _getPetName() {
    if (level == 1) return "Aura Egg";
    if (level == 2) return "Hatchling";
    if (level == 3) return "Spark";
    if (level == 4) return "Aura Bird";
    return "Nebula Dragon";
  }

  @override
  Widget build(BuildContext context) {
    int requiredExp = level * 50;
    double progress = exp / requiredExp;
    Color auraColor = _getAuraColor();

    return GestureDetector(
      onTap: () {
        // Optional: Show pet stats dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: auraColor.withOpacity(0.3))),
            title: Text("Aura Pet Status", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getPetEmoji(), style: const TextStyle(fontSize: 60)),
                const SizedBox(height: 10),
                Text(_getPetName(), style: GoogleFonts.outfit(color: auraColor, fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text("Level $level", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(auraColor),
                  ),
                ),
                const SizedBox(height: 5),
                Text("$exp / $requiredExp XP to Next Level", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 15),
                Text("Complete Tasks, Reminders, and Notes to earn XP and evolve your pet!", 
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: auraColor.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: auraColor.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ]
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji Avatar with subtle floating animation
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [auraColor.withOpacity(0.3), Colors.transparent],
                  radius: 0.8,
                ),
              ),
              child: Text(
                _getPetEmoji(),
                style: const TextStyle(fontSize: 20),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
               .moveY(begin: -1, end: 1, duration: 2.seconds),
            ),
            
            const SizedBox(width: 8),
            
            // Level and Progress Bar Column
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Lv. $level",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // Custom mini progress bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: auraColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(color: auraColor.withOpacity(0.5), blurRadius: 4),
                        ]
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class CategoryFolder extends StatefulWidget {
  final String category;
  final List<SavedItem> items;
  final Function(String) onToggleItem;
  final Function(String) onDeleteItem;

  const CategoryFolder({
    super.key,
    required this.category,
    required this.items,
    required this.onToggleItem,
    required this.onDeleteItem,
  });

  @override
  State<CategoryFolder> createState() => _CategoryFolderState();
}

class _CategoryFolderState extends State<CategoryFolder> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Folder Header
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 4, 
                    height: 18, 
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1), 
                      borderRadius: BorderRadius.circular(2)
                    )
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.category.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${widget.items.length}",
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          
          // Folder Content
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: widget.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Dismissible(
                      key: Key(item.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => widget.onDeleteItem(item.id),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.2), 
                          borderRadius: BorderRadius.circular(20)
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      ),
                      child: SavedItemCard(
                        item: item,
                        onTap: () => widget.onToggleItem(item.id),
                      ),
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0),
                  );
                }).toList(),
              ),
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}
