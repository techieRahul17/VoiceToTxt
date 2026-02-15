import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui'; // For ImageFilter

// --- Models ---

enum ItemCategory { reminder, todo, note }

class SavedItem {
  final String text;
  final ItemCategory category;
  final DateTime timestamp;

  SavedItem({
    required this.text,
    required this.category,
    required this.timestamp,
  });
}

// --- Main Screen ---

class VoiceFlowScreen extends StatefulWidget {
  const VoiceFlowScreen({super.key});

  @override
  State<VoiceFlowScreen> createState() => _VoiceFlowScreenState();
}

class _VoiceFlowScreenState extends State<VoiceFlowScreen> with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _currentText = "Press the mic and start speaking...";
  final List<SavedItem> _savedItems = [];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.8,
      upperBound: 1.2,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _initSpeech() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' && _isListening) {
          // Logic to auto-save when speech stops naturally could go here, 
          // but usually controlled by manual stop or detailed status checks.
          // For this demo, we'll save on manual stop or recognized result finalization.
        }
      },
      onError: (error) => debugPrint("Error: $error"),
    );
    if (!available) {
      debugPrint("Speech recognition not available");
    }
  }

  void _startListening() async {
    if (!_speech.isAvailable) {
      _initSpeech(); // Try initializing again
      return;
    }

    await _speech.listen(
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

    setState(() {
      _isListening = true;
      _currentText = "Listening...";
      _pulseController.repeat(reverse: true);
    });
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _pulseController.stop();
      _pulseController.reset();
    });
    // Ensure we reset text instruction if nothing was captured
    if (_currentText == "Listening...") {
        setState(() {
            _currentText = "Press the mic and start speaking...";
        });
    }
  }

  void _saveReceivedText(String text) {
    if (text.isEmpty) return;

    final category = _detectIntent(text);
    final newItem = SavedItem(
      text: text,
      category: category,
      timestamp: DateTime.now(),
    );

    setState(() {
      _savedItems.insert(0, newItem);
      _currentText = "Press the mic and start speaking..."; // Reset logic
    });
    
    // Placeholder for local storage logic
    _saveToLocalStorage(newItem);
  }

  ItemCategory _detectIntent(String text) {
    final lowerText = text.toLowerCase();
    if (lowerText.contains("remind me")) {
      return ItemCategory.reminder;
    } else if (lowerText.contains("todo") || lowerText.contains("task")) {
      return ItemCategory.todo;
    } else {
      return ItemCategory.note;
    }
  }

  void _saveToLocalStorage(SavedItem item) {
    // TODO: Implement Hive or SharedPrefs logic here
    debugPrint("Saving to local storage: ${item.text} [${item.category}]");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "VoiceFlow",
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Gradient (Optional subtle effect)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purple.withValues(alpha: 0.15),
                boxShadow: [
                   BoxShadow(
                     color: Colors.purple.withValues(alpha: 0.15),
                     blurRadius: 100,
                     spreadRadius: 20,
                   ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.15),
                boxShadow: [
                   BoxShadow(
                     color: Colors.blue.withValues(alpha: 0.15),
                     blurRadius: 100,
                     spreadRadius: 20,
                   ),
                ],
              ),
            ),
          ),

          // Main Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live Transcription Area
                GlassCard(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 120),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Wait for input...",
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _currentText,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                
                // Saved Items Header
                Text(
                  "Recent Captures",
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 15),

                // Saved Items List
                Expanded(
                  child: _savedItems.isEmpty
                      ? Center(
                          child: Text(
                            "No voice notes yet.",
                            style: GoogleFonts.poppins(color: Colors.white38),
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _savedItems.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return SavedItemCard(item: _savedItems[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ScaleTransition(
        scale: _pulseController,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _isListening
                    ? Colors.blueAccent.withValues(alpha: 0.6)
                    : Colors.transparent,
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: FloatingActionButton.large(
            onPressed: _isListening ? _stopListening : _startListening,
            backgroundColor: _isListening ? const Color(0xFF2196F3) : const Color(0xFF2C2C2C),
            elevation: 10,
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Reusable Widgets ---

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SavedItemCard extends StatelessWidget {
  final SavedItem item;

  const SavedItemCard({super.key, required this.item});

  Color getCategoryColor() {
    switch (item.category) {
      case ItemCategory.reminder:
        return Colors.purpleAccent; // Purple for Reminder
      case ItemCategory.todo:
        return Colors.greenAccent; // Green for Todo
      case ItemCategory.note:
        return Colors.blueAccent; // Blue for Note
    }
  }

  String getCategoryLabel() {
    switch (item.category) {
      case ItemCategory.reminder:
        return "Reminder";
      case ItemCategory.todo:
        return "Todo";
      case ItemCategory.note:
        return "Note";
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: getCategoryColor(),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: getCategoryColor().withValues(alpha: 0.5),
                  blurRadius: 8,
                )
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      getCategoryLabel().toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: getCategoryColor(),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      "${item.timestamp.hour}:${item.timestamp.minute.toString().padLeft(2, '0')}",
                      style: GoogleFonts.poppins(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.text,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0);
  }
}
