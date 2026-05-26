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

  Future<void> _loadSavedUuid() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user_uuid');
    if (saved != null) _uuidController.text = saved;
  }

  Future<void> _saveUuid(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_uuid', uuid);
  }

  Future<void> _loadServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final res = await http.get(Uri.parse('http://srv.rsfly.pro/srv.txt'));
      if (res.statusCode == 200) {
        setState(() {
          _servers = res.body.split('\n').map((e) => e.trim()).where((e) => e.contains(':')).toList();
          if (_servers.isNotEmpty) _selectedServer = _servers.first;
        });
      }
    } catch (_) {}
    setState(() => _isLoadingServers = false);
  }

  Future<void> _connect() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isEmpty) {
      AcrylicToast.show(context, 'لطفاً رمز خود را وارد کنید', isError: true);
      return;
    }

    await _saveUuid(uuid);

    if (_selectedServer == null) return;

    final parts = _selectedServer!.split(':');
    final ip = parts[0];
    final port = int.parse(parts[1]);

    final profile = VlessProfile(
      id: const Uuid().v4(),
      name: 'RsFly',                    // نام کوتاه — دیگر VLESS-TCP نشان نمی‌دهد
      host: ip,
      port: port,
      uuid: uuid,
      security: 'none',                 // دقیقاً همان چیزی که خواستی
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
      AcrylicToast.show(context, 'رمز خود را وارد کنید', isError: true);
      return;
    }

    setState(() => _balanceInfo = 'در حال دریافت...');

    try {
      final response = await http.get(Uri.parse('http://185.204.197.76:2096/sub/$uuid'));
      if (response.statusCode == 200) {
        final match = RegExp(r'Remained\s*([\d.]+\s*GB)', caseSensitive: false).firstMatch(response.body);
        final remained = match?.group(1) ?? 'نامشخص';
        setState(() => _balanceInfo = 'موجودی باقی‌مانده: $remained');
      } else {
        setState(() => _balanceInfo = 'خطا در دریافت اطلاعات');
      }
    } catch (e) {
      setState(() => _balanceInfo = 'خطا در اتصال');
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
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _uuidController,
              decoration: const InputDecoration(
                labelText: 'رمز شما',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            if (_isLoadingServers)
              const CircularProgressIndicator()
            else
              DropdownButtonFormField<String>(
                value: _selectedServer,
                decoration: const InputDecoration(labelText: 'انتخاب سرور', border: OutlineInputBorder()),
                items: _servers.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _selectedServer = v),
              ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isConnected ? () => context.read<VpnNotifier>().disconnect() : _connect,
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
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),

            const SizedBox(height: 20),

            if (_balanceInfo.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Text(_balanceInfo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              ),

            const Spacer(),
            Text('وضعیت: ${vpn.status.toString().split('.').last}'),
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
