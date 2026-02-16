import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';

// --- Models ---

enum ItemCategory { reminder, todo, note }

class SavedItem {
  final String id;
  final String text;
  final ItemCategory category;
  final DateTime timestamp;
  bool isCompleted;

  SavedItem({
    required this.id,
    required this.text,
    required this.category,
    required this.timestamp,
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
  
  // Animation controllers/effects are handled via flutter_animate, 
  // but we keep a simple one for the mic pulse if needed, 
  // though flutter_animate's loop is easier.

  @override
  void initState() {
    super.initState();
    _initSpeech();
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

  void _saveReceivedText(String text, {ItemCategory? manualCategory}) {
    if (text.trim().isEmpty) return;

    final category = manualCategory ?? _detectIntent(text);
    final newItem = SavedItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      category: category,
      timestamp: DateTime.now(),
    );

    setState(() {
      _savedItems.insert(0, newItem);
      _currentText = "";
    });
    
    // Simulate storage
    debugPrint("Saved: ${newItem.text}");
  }

  ItemCategory _detectIntent(String text) {
    final lower = text.toLowerCase();
    if (lower.contains("remind") || lower.contains("remember")) return ItemCategory.reminder;
    if (lower.contains("todo") || lower.contains("task") || lower.contains("buy") || lower.contains("fix")) return ItemCategory.todo;
    return ItemCategory.note;
  }

  void _deleteItem(String id) {
    setState(() {
      _savedItems.removeWhere((item) => item.id == id);
    });
  }

  void _toggleItemCompletion(String id) {
    setState(() {
      final index = _savedItems.indexWhere((item) => item.id == id);
      if (index != -1) {
        _savedItems[index].isCompleted = !_savedItems[index].isCompleted;
      }
    });
  }

  void _showManualInputModal() {
    ItemCategory selectedCategory = ItemCategory.note;
    _manualInputController.clear();

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
                    Row(
                      children: [
                        _buildCategoryChip(
                          isSelected: selectedCategory == ItemCategory.note,
                          label: "Note",
                          color: Colors.blueAccent,
                          onTap: () => setModalState(() => selectedCategory = ItemCategory.note),
                        ),
                        const SizedBox(width: 10),
                        _buildCategoryChip(
                          isSelected: selectedCategory == ItemCategory.todo,
                          label: "Todo",
                          color: Colors.greenAccent,
                          onTap: () => setModalState(() => selectedCategory = ItemCategory.todo),
                        ),
                        const SizedBox(width: 10),
                        _buildCategoryChip(
                          isSelected: selectedCategory == ItemCategory.reminder,
                          label: "Reminder",
                          color: Colors.purpleAccent,
                          onTap: () => setModalState(() => selectedCategory = ItemCategory.reminder),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          _saveReceivedText(_manualInputController.text, manualCategory: selectedCategory);
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

  Widget _buildCategoryChip({
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
  
  // Correction for the chip logic above:
  // Since `selectedCategory` needs to be updated, we can just do:
  Widget _buildCategoryChipReal(StateSetter setModalState, ItemCategory Function() getCat, Function(ItemCategory) setCat, ItemCategory target, String label, Color color) {
    bool isSelected = getCat() == target;
    return GestureDetector(
      onTap: () => setModalState(() => setCat(target)),
      child: Container( // Removed AnimatedContainer for simpler state reconstruction
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
      ),
    );
  }


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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                        child: const Icon(Icons.person_outline, color: Colors.white70),
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

                // List Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text("YOUR FLOW", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w800)),
                  ),
                ),
                
                const SizedBox(height: 15),

                // List
                Expanded(
                  child: _savedItems.isEmpty
                      ? Center(child: Text("No items yet.", style: GoogleFonts.outfit(color: Colors.white24)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _savedItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = _savedItems[index];
                            return Dismissible(
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
                            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0);
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
    switch (item.category) {
      case ItemCategory.reminder: return const Color(0xFFA855F7); // Purple
      case ItemCategory.todo: return const Color(0xFF22D3EE); // Cyan
      case ItemCategory.note: return const Color(0xFFF472B6); // Pink
    }
  }

  IconData _getIcon() {
    switch (item.category) {
      case ItemCategory.reminder: return Icons.alarm;
      case ItemCategory.todo: return Icons.check_circle_outline;
      case ItemCategory.note: return Icons.sticky_note_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Category Indicator / Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_getIcon(), color: color, size: 20),
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
                      color: Colors.white.withOpacity(item.isCompleted ? 0.4 : 0.9),
                      fontSize: 16,
                      decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${item.category.name.toUpperCase()} • ${item.timestamp.hour}:${item.timestamp.minute.toString().padLeft(2, '0')}",
                    style: GoogleFonts.outfit(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            
            // Checkbox (Custom) -> Only for Todo maybe? Or all for "Done" status
            if (item.category == ItemCategory.todo) 
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: item.isCompleted ? color : Colors.white24, width: 2),
                  color: item.isCompleted ? color : Colors.transparent,
                ),
                child: item.isCompleted ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
              ),
          ],
        ),
      ),
    );
  }
}
