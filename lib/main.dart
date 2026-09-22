import 'package:flutter/material.dart';
import 'core/db.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.instance.init();
  runApp(const CementApp());
}
