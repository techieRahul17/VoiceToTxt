import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'voice_flow_screen.dart';

void main() {
  runApp(const VoiceFlowApp());
}

class VoiceFlowApp extends StatelessWidget {
  const VoiceFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.poppinsTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: const VoiceFlowScreen(),
    );
  }
}
