import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stored_vpn_profile.dart';
import '../models/vless_profile.dart';
import '../models/vless_types.dart';
import '../notifiers/profile_notifier.dart';
import '../notifiers/vpn_notifier.dart';
import '../widgets/acrylic_toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _uuidController = TextEditingController();
  String? _selectedServer;
  List<String> _servers = [];
  bool _isLoadingServers = false;
  String _balanceInfo = '';

  @override
  void initState() {
    super.initState();
    _loadSavedUuid();
    _loadServers();
  }

  // ذخیره و بارگذاری رمز (UUID)
  Future<void> _loadSavedUuid() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUuid = prefs.getString('user_uuid');
    if (savedUuid != null && savedUuid.isNotEmpty) {
      _uuidController.text = savedUuid;
    }
  }

  Future<void> _saveUuid(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_uuid', uuid);
  }

  Future<void> _loadServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final response = await http.get(Uri.parse('https://srv.rsfly.pro/srv.txt'));
      if (response.statusCode == 200) {
        setState(() {
          _servers = response.body
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty && e.contains(':'))
              .toList();
          if (_servers.isNotEmpty && _selectedServer == null) {
            _selectedServer = _servers.first;
          }
        });
      }
    } catch (e) {
      if (mounted) AcrylicToast.show(context, 'خطا در بارگذاری سرورها', isError: true);
    } finally {
      setState(() => _isLoadingServers = false);
    }
  }

  Future<void> _connect() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isEmpty) {
      AcrylicToast.show(context, 'لطفاً رمز خود را وارد کنید', isError: true);
      return;
    }

    await _saveUuid(uuid); // ذخیره رمز برای دفعات بعدی

    if (_selectedServer == null) {
      AcrylicToast.show(context, 'سرور انتخاب نشده', isError: true);
      return;
    }

    final parts = _selectedServer!.split(':');
    final ip = parts[0];
    final port = int.parse(parts[1]);

    final profile = VlessProfile(
      id: const Uuid().v4(),
      name: 'RsFly Connection',
      host: ip,
      port: port,
      uuid: uuid,
      security: 'none',
      encryption: 'none',
      transport: VlessTransport.tcp,
      path: '',
      hostHeader: '',
      sni: '',
      remark: 'RsFly',
    );

    final notifier = context.read<ProfileNotifier>();
    final vpn = context.read<VpnNotifier>();

    await notifier.addOrUpdate(VlessStoredVpnProfile(profile));
    await notifier.setActive(profile.id);

    final success = await vpn.connect(VlessStoredVpnProfile(profile));
    if (mounted) {
      AcrylicToast.show(context, success ? 'در حال اتصال...' : 'اتصال ناموفق', isError: !success);
    }
  }

  Future<void> _checkBalance() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isEmpty) {
      AcrylicToast.show(context, 'ابتدا رمز خود را وارد کنید', isError: true);
      return;
    }

    setState(() => _balanceInfo = 'در حال دریافت اطلاعات...');

    try {
      final url = 'http://185.204.197.76:2096/sub/$uuid';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = response.body;

        // استخراج مقدار Remained
        final match = RegExp(r'Remained\s*([\d.]+\s*[A-Za-z]+)').firstMatch(body);
        final remained = match?.group(1) ?? 'نامشخص';

        setState(() {
          _balanceInfo = 'موجودی باقی‌مانده: $remained';
        });
      } else {
        setState(() => _balanceInfo = 'خطا در دریافت اطلاعات');
      }
    } catch (e) {
      setState(() => _balanceInfo = 'خطا در اتصال به سرور');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnNotifier>();
    final isConnected = vpn.status == VpnStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RsFly VPN 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _uuidController,
              decoration: const InputDecoration(
                labelText: 'رمز شما',
                border: OutlineInputBorder(),
                hintText: '6ec34d88-cc3f-4fdd-bc60-f72a266dca06',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            if (_isLoadingServers)
              const CircularProgressIndicator()
            else
              DropdownButtonFormField<String>(
                value: _selectedServer,
                decoration: const InputDecoration(
                  labelText: 'انتخاب سرور',
                  border: OutlineInputBorder(),
                ),
                items: _servers.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _selectedServer = v),
              ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isConnected 
                    ? () => context.read<VpnNotifier>().disconnect() 
                    : _connect,
                icon: Icon(isConnected ? Icons.stop : Icons.play_arrow),
                label: Text(isConnected ? 'قطع اتصال' : 'اتصال'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _checkBalance,
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('چک بالانس'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  foregroundColor: Colors.orange,
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_balanceInfo.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Text(
                  _balanceInfo,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              ),

            const Spacer(),

            Text(
              'وضعیت: ${vpn.status.toString().split('.').last}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _uuidController.dispose();
    super.dispose();
  }
}
