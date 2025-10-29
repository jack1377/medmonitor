import 'package:flutter/material.dart';
import 'package:sms_advanced/sms_advanced.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// === مدل داده ===
class VitalData {
  static double hr = 0, spo2 = 0, temp = 0;
  static void update(Map<String, double> data) {
    hr = data['HR'] ?? 0;
    spo2 = data['SPO2'] ?? 0;
    temp = data['TEMP'] ?? 0;
  }
}

// === سرویس SMS ===
class SmsService {
  static final SmsService _instance = SmsService._();
  factory SmsService() => _instance;
  SmsService._() {
    _init();
  }

  String _deviceNumber = "+989123456789";

  Future<void> _init() async {
    await [Permission.sms, Permission.phone].request();
    await _loadNumber();
    SmsReceiver().onSmsReceived!.listen(_onSmsReceived);
  }

  Future<void> _loadNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('device_number');
    if (saved != null && saved.isNotEmpty) _deviceNumber = saved;
  }

  Future<void> saveNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_number', number);
    _deviceNumber = number;
  }

  Future<void> requestState() async {
    final sms = SmsMessage(_deviceNumber, "STATE");
    await SmsSender().sendSms(sms);
  }

  void _onSmsReceived(SmsMessage msg) {
    if (msg.sender == _deviceNumber &&
        msg.body != null &&
        msg.body!.contains("HR:")) {
      final data = <String, double>{};
      final regex = RegExp(r'([A-Z]+):([0-9.]+)');
      for (var m in regex.allMatches(msg.body!)) {
        data[m.group(1)!] = double.parse(m.group(2)!);
      }
      VitalData.update(data);
    }
  }

  String get deviceNumber => _deviceNumber;
}

// === ویجت کارت داده ===
class VitalCard extends StatelessWidget {
  final String title, value, unit;
  final Color color;
  const VitalCard(
      {super.key,
      required this.title,
      required this.value,
      required this.unit,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: color,
            child: Text(
              value.isNotEmpty ? value[0] : '?',
              style: const TextStyle(color: Colors.white),
            )),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("$value $unit", style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

// === گراف ساده PPG ===
class PpgChart extends StatefulWidget {
  const PpgChart({super.key});
  @override
  State<PpgChart> createState() => _PpgChartState();
}

class _PpgChartState extends State<PpgChart> {
  final List<double> data = [];
  late Timer timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        data.add(VitalData.hr);
        if (data.length > 20) data.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          height: 120,
          child: CustomPaint(painter: LineChartPainter(data)),
        ),
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  LineChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    final double dx = size.width / (data.length - 1);
    final maxY = data.reduce((a, b) => a > b ? a : b);
    final scaleY = size.height / (maxY + 10);
    for (int i = 0; i < data.length - 1; i++) {
      canvas.drawLine(
        Offset(i * dx, size.height - data[i] * scaleY),
        Offset((i + 1) * dx, size.height - data[i + 1] * scaleY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// === اپلیکیشن ===
void main() {
  runApp(const MedMonitorApp());
}

class MedMonitorApp extends StatelessWidget {
  const MedMonitorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedMonitor™ Pro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// === صفحه اصلی ===
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final smsService = SmsService();
  bool isLoading = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = smsService.deviceNumber;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MedMonitor™ Pro"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : _requestData,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white))
                  : const Icon(Icons.sync, color: Colors.white),
              label: Text(isLoading ? "در حال دریافت..." : "دریافت وضعیت"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                VitalCard(
                    title: "ضربان قلب",
                    value: VitalData.hr.toStringAsFixed(0),
                    unit: "BPM",
                    color: Colors.red),
                VitalCard(
                    title: "اکسیژن خون",
                    value: VitalData.spo2.toStringAsFixed(0),
                    unit: "%",
                    color: Colors.blue),
                VitalCard(
                    title: "دما",
                    value: VitalData.temp.toStringAsFixed(1),
                    unit: "°C",
                    color: Colors.orange),
                const SizedBox(height: 16),
                const PpgChart(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestData() async {
    setState(() => isLoading = true);
    await smsService.requestState();
    setState(() => isLoading = false);
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تنظیم شماره دستگاه"),
        content: TextField(
          controller: _controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: "مثال: +989123456789",
            prefixText: "+98 ",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("لغو")),
          ElevatedButton(
            onPressed: () {
              final number = "+98${_controller.text.trim()}";
              smsService.saveNumber(number);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("ذخیره شد: $number")));
            },
            child: const Text("ذخیره"),
          ),
        ],
      ),
    );
  }
}
