import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;

class VoiceExpensePage extends StatefulWidget {
  const VoiceExpensePage({super.key});

  @override
  State<VoiceExpensePage> createState() => _VoiceExpensePageState();
}

class _VoiceExpensePageState extends State<VoiceExpensePage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _text = "";

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  void _startListening() async {
    setState(() => _listening = true);

    await _speech.listen(
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (res) {
        setState(() => _text = res.recognizedWords);
      },
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  // ----------------------------------------------------
  // PARSER (Full Dynamic Parsing)
  // ----------------------------------------------------

  /// Extract category from "category X ..." (supports 'category', 'type', 'tag', 'for')
  String? extractCategory(String input) {
    final match =
        RegExp(r'\b(category|type|tag|for)\s+(.+)$', caseSensitive: false)
            .firstMatch(input);
    if (match != null) {
      return match.group(2)!.trim();
    }
    return null;
  }

  /// Try to extract a decimal from digits, e.g. "£25.34" or "25.34" or "25"
  double? extractNumberDigits(String input) {
    // Prefer £-prefixed numbers if present (user is in GBP)
    final poundFirst = RegExp(r'£\s*(\d+(?:\.\d+)?)').firstMatch(input);
    if (poundFirst != null) {
      return double.tryParse(poundFirst.group(1)!);
    }

    // General first numeric
    final m = RegExp(r'\b\d+(?:\.\d+)?\b').firstMatch(input);
    if (m != null) return double.tryParse(m.group(0)!);
    return null;
  }

  /// Specialized handler for "X pounds Y pence" or "X pound Y pence" (digits)
  /// e.g., "25 pounds 34 pence" => 25.34
  double? extractPoundsPenceDigits(String input) {
    final m = RegExp(
      r'\b(\d+)\s*(?:pounds?|quid|gbp|£)?\s+(\d{1,2})\s*pence\b',
      caseSensitive: false,
    ).firstMatch(input);
    if (m != null) {
      final pounds = int.tryParse(m.group(1)!);
      final pence = int.tryParse(m.group(2)!);
      if (pounds != null && pence != null) {
        return pounds + (pence / 100.0);
      }
    }
    return null;
  }

  /// Converts number words (and hybrid forms) into a double.
  /// Supports:
  ///  - "twenty five"
  ///  - "one hundred and two"
  ///  - "twenty five point three four"
  ///  - "twenty five pounds thirty four pence"
  ///  - digits mixed into words ("twenty five point 34")
  double? extractNumberWords(String text) {
    final words = text.toLowerCase();

    // Fast path: "X pounds Y pence" where X and/or Y are number words
    final poundsPenceWords = _extractPoundsPenceWords(words);
    if (poundsPenceWords != null) return poundsPenceWords;

    // General word-to-number with optional "point ..."
    final tokens = words
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // Maps
    final small = <String, int>{
      'zero': 0,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19,
    };
    final tens = <String, int>{
      'twenty': 20,
      'thirty': 30,
      'forty': 40,
      'fifty': 50,
      'sixty': 60,
      'seventy': 70,
      'eighty': 80,
      'ninety': 90,
    };
    final scale = <String, int>{'hundred': 100, 'thousand': 1000};

    double total = 0;
    double current = 0;
    bool decimalMode = false;
    double decimalFactor = 0.1;

    bool sawNumberToken = false;

    for (var p in tokens) {
      if (p == 'and') continue;

      if (p == 'point') {
        decimalMode = true;
        continue;
      }

      // Plain digits inside words stream (e.g., "point 34")
      if (RegExp(r'^\d+$').hasMatch(p)) {
        sawNumberToken = true;
        final val = int.parse(p);
        if (!decimalMode) {
          current += val;
        } else {
          // append each digit into decimal places
          for (final ch in p.split('')) {
            current += int.parse(ch) * decimalFactor;
            decimalFactor /= 10.0;
          }
        }
        continue;
      }

      if (small.containsKey(p)) {
        sawNumberToken = true;
        final val = small[p]!.toDouble();
        if (!decimalMode) {
          current += val;
        } else {
          current += val * decimalFactor;
          decimalFactor /= 10.0;
        }
        continue;
      }

      if (tens.containsKey(p)) {
        sawNumberToken = true;
        final val = tens[p]!.toDouble();
        if (!decimalMode) {
          current += val;
        } else {
          current += val * decimalFactor;
          decimalFactor /= 10.0;
        }
        continue;
      }

      if (scale.containsKey(p)) {
        sawNumberToken = true;
        final s = scale[p]!;
        if (!decimalMode) {
          if (current == 0) current = 1; // "hundred" alone = 100
          current *= s;
          if (s >= 1000) {
            total += current;
            current = 0;
          }
        } else {
          // Unusual: ignore scale in decimal mode
        }
        continue;
      }

      // Ignore all other tokens until currency markers (handled elsewhere)
    }

    final result = total + current;
    if (!sawNumberToken) return null;
    return result == 0 ? null : double.parse(result.toStringAsFixed(2));
  }

  /// Try to parse "X pounds Y pence" where X and Y are number-words or digits.
  /// Returns double or null.
  double? _extractPoundsPenceWords(String input) {
    // Capture text between bounds to isolate the phrase
    final m = RegExp(
      r'\b(.+?)\s*(?:pounds?|quid|gbp|£)\s+(.+?)\s*pence\b',
      caseSensitive: false,
    ).firstMatch(input);
    if (m == null) return null;

    final left = m.group(1)!.trim();
    final right = m.group(2)!.trim();

    final leftVal = _wordsOrDigitsToNumber(left);
    final rightVal = _wordsOrDigitsToNumber(right);

    if (leftVal == null || rightVal == null) return null;

    // Right side is pence; clamp to [0, 99]
    final p = rightVal.round().clamp(0, 99);
    return leftVal + (p / 100.0);
  }

  /// Convert a small phrase that might be number-words or digits into a number.
  double? _wordsOrDigitsToNumber(String phrase) {
    final trimmed = phrase.trim();
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) {
      return double.tryParse(trimmed);
    }
    // Fall back to word parsing for the isolated fragment
    final tokens = trimmed
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final small = <String, int>{
      'zero': 0,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19,
    };
    final tens = <String, int>{
      'twenty': 20,
      'thirty': 30,
      'forty': 40,
      'fifty': 50,
      'sixty': 60,
      'seventy': 70,
      'eighty': 80,
      'ninety': 90,
    };
    final scale = <String, int>{'hundred': 100, 'thousand': 1000};

    double total = 0;
    double current = 0;

    for (final p in tokens) {
      if (p == 'and') continue;

      if (RegExp(r'^\d+$').hasMatch(p)) {
        current += double.parse(p);
        continue;
      }
      if (small.containsKey(p)) {
        current += small[p]!;
        continue;
      }
      if (tens.containsKey(p)) {
        current += tens[p]!;
        continue;
      }
      if (scale.containsKey(p)) {
        if (current == 0) current = 1;
        current *= scale[p]!;
        if (scale[p]! >= 1000) {
          total += current;
          current = 0;
        }
        continue;
      }
    }

    final result = total + current;
    return result == 0 ? null : result.toDouble();
  }

  Future<void> _processAndSend() async {
    final input = _text.toLowerCase();

    // 1) Category from "category/type/tag/for ..."
    final category = extractCategory(input);

    // 2) Amount (try the most specific patterns first)
    double? amount =
        extractPoundsPenceDigits(input) ?? // e.g., "25 pounds 34 pence"
            extractNumberDigits(input) ?? // e.g., "£25.34" or "25.34"
            extractNumberWords(input); // e.g., "twenty five point three four"

    if (amount == null || category == null) {
      _show("Could not parse amount or category.");
      return;
    }

    // Round to 2dp for currency
    amount = double.parse(amount.toStringAsFixed(2));

    try {
      final response = await http.post(
        Uri.parse("https://beatporttopcharts.com/php/api/expense/save_expense.php"),
        body: {"amount": amount.toString(), "category": category},
      );

      if (response.statusCode == 200) {
        _show("Saved: £$amount ($category)");
      } else {
        _show("Error saving data (${response.statusCode}).");
      }
    } catch (e) {
      _show("Network error: $e");
    }
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice Expense Logger")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_text, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _listening ? null : _startListening,
                  child: const Text("Start"),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: !_listening ? null : _stopListening,
                  child: const Text("Stop"),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _processAndSend,
                  child: const Text("Save"),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
