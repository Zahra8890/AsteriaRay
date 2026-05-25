import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
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
  List<String> _balanceServers = [];
  bool _isLoadingServers = false;

  @override
  void initState() {
    super.initState();
    _loadServers();
    _loadSavedUuid();
  }

  Future<void> _loadSavedUuid() async {
    final notifier = context.read<ProfileNotifier>();
    await notifier.init();
    if (notifier.profiles.isNotEmpty) {
      final p = notifier.profiles.first;
      if (p is VlessStoredVpnProfile) {
        _uuidController.text = p.profile.uuid;
      }
    }
  }

  Future<void> _loadServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final srv = await HttpClient().getUrl(Uri.parse('http://panel.rsfly.pro/srv.txt'));
      final bal = await HttpClient().getUrl(Uri.parse('http://panel.rsfly.pro/bal.txt'));

      final srvResp = await srv.close();
      final balResp = await bal.close();

      final srvText = await srvResp.transform(SystemEncoding().decoder).join();
      final balText = await balResp.transform(SystemEncoding().decoder).join();

      setState(() {
        _servers = srvText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty && e.contains(':')).toList();
        _balanceServers = balText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty && e.contains(':')).toList();
        if (_servers.isNotEmpty && _selectedServer == null) {
          _selectedServer = _servers.first;
        }
      });
    } catch (e) {
      if (mounted) {
        AcrylicToast.show(context, 'خطا در بارگذاری سرورها', isError: true);
      }
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
      transport: VlessTransport.ws,
      path: '/ws',
      hostHeader: ip,
      sni: '',
      remark: 'RsFly Dynamic',
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
    if (_balanceServers.isEmpty) {
      AcrylicToast.show(context, 'لیست بالانس خالی است', isError: true);
      return;
    }

    final server = _balanceServers.first;
    final parts = server.split(':');
    final ip = parts[0];
    final port = int.parse(parts[1]);

    final uuid = _uuidController.text.trim();
    if (uuid.isEmpty) {
      AcrylicToast.show(context, 'ابتدا رمز خود را وارد کنید', isError: true);
      return;
    }

    final profile = VlessProfile(
      id: const Uuid().v4(),
      name: 'Balance Check',
      host: ip,
      port: port,
      uuid: uuid,
      security: 'none',
      encryption: 'none',
      transport: VlessTransport.ws,
      path: '/ws',
      hostHeader: ip,
    );

    final vpn = context.read<VpnNotifier>();
    final success = await vpn.connect(VlessStoredVpnProfile(profile));

    if (mounted) {
      AcrylicToast.show(context, success ? 'در حال چک بالانس...' : 'اتصال ناموفق', isError: !success);
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
            // UUID Input → تغییر به "رمز شما"
            TextField(
              controller: _uuidController,
              decoration: const InputDecoration(
                labelText: 'رمز شما',
                border: OutlineInputBorder(),
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Server Selector
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

            // Start / Stop Button
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

            // Check Balance Button
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

            const Spacer(),

            Text(
              'وضعیت: ${vpn.status.toString().split('.').last}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
