import 'package:flutter/material.dart';
import '../data/attendance_repository.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late Future<List<Map<String, dynamic>>> _history;
  Map<String, dynamic>? _current;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final current = await AttendanceRepository.current();
    if (!mounted) return;
    setState(() {
      _current = current;
      _history = AttendanceRepository.getAll();
    });
  }

  Future<void> _toggle() async {
    try {
      if (_current == null) {
        await AttendanceRepository.clockIn();
      } else {
        await AttendanceRepository.clockOut();
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attendance')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _toggle,
            icon: Icon(
              _current == null ? Icons.login_rounded : Icons.logout_rounded,
            ),
            label: Text(_current == null ? 'Clock in' : 'Clock out'),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return const Center(child: Text('No attendance records yet.'));
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(row['user_name']?.toString() ?? 'Employee'),
                    subtitle: Text('In: ${row['clock_in_at']}'),
                    trailing: Text(row['clock_out_at']?.toString() ?? 'Open'),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
