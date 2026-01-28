import 'package:flutter/material.dart';
import 'pages/expenses_dashboard_page.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';      // for dates
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/number_symbols_data.dart';

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Expense Tracker',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark(),
//       home: const ExpensesDashboardPage(),
//     );
//   }
// }



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Choose your default locale
  const appLocale = 'en_GB';

  // Initialize locale data for intl BEFORE any DateFormat/NumberFormat usage
  await initializeDateFormatting(appLocale, null);
  // await initializeNumberFormatting(appLocale);

  // Set the default locale for Intl
  Intl.defaultLocale = appLocale;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Expenses',
      // Tell Flutter which locales your app supports
      supportedLocales: const [
        Locale('en', 'GB'),
        // add more if needed
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ExpensesDashboardPage(), // your dashboard widget
    );
  }
}
