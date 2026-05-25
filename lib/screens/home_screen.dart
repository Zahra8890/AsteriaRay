import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../models/vless_profile.dart';
import '../models/vpn_protocol.dart';
import '../notifiers/profile_notifier.dart';
import '../notifiers/vpn_notifier.dart';
import '../widgets/acrylic_toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _idController = TextEditingController();
  bool _isFetching = false;
  String _networkStatus = "وضعیت: قطع شده";

  final String _srvUrl = "http://srv.rsfly.pro/srv.txt";
  final String _balUrl = "http://srv.rsfly.pro/bal.txt";

  // ۱. منطق دریافت آنلاین سرور و استارت زدن VPN پروژه‌ی AsteriaRay
  Future<void> _handleVpnToggle(VpnNotifier vpnNotifier) async {
    final vlessId = _idController.text.trim();
    if (vlessId.isEmpty) {
      AcrylicToast.show(context, 'لطفاً ابتدا آیدی VLESS را وارد کنید', icon: Icons.warning_rounded);
      return;
    }

    // اگر متصل یا در حال اتصال بود، دیسکانکت کن
    if (vpnNotifier.status == VpnStatus.connected || vpnNotifier.status == VpnStatus.connecting) {
      await vpnNotifier.disconnect();
      setState(() {
        _networkStatus = "وضعیت: قطع شده";
      });
      return;
    }

    setState(() {
      _isFetching = true;
      _networkStatus = "در حال دریافت آدرس سرور...";
    });

    try {
      final response = await http.get(Uri.parse(_srvUrl));
      if (response.statusCode == 200) {
        // پیدا کردن اولین خط حاوی اطلاعات سرور
        final serverLine = response.body.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => "");
        
        if (serverLine.contains(':')) {
          final parts = serverLine.split(':');
          final ip = parts[0].trim();
          final port = int.parse(parts[1].trim());

          // ساخت آبجکت نیتیو VlessProfile مطابق با پکیج مدل‌های AsteriaRay
          final dynamicProfile = VlessStoredVpnProfile(
            id: 'dynamic_active_profile',
            name: 'RSFly Dynamic',
            protocol: VpnProtocol.vless,
            profile: VlessProfile(
              name: 'RSFly Dynamic',
              host: ip,
              port: port,
              uuid: vlessId,
              encryption: 'none',
              network: 'ws', // ساختار پیش‌فرض، بر اساس سرور قابل تغییر است
              security: 'none',
            ),
          );

          setState(() {
            _networkStatus = "در حال اتصال به هسته Xray...";
          });

          // متصل کردن هسته با استفاده از کنترلر اصلی پروژه
          final success = await vpnNotifier.connect(dynamicProfile);
          
          setState(() {
            _networkStatus = success ? "متصل به سرور: $ip" : "خطا در برقراری تونل امن";
          });
        } else {
          setState(() => _networkStatus = "خطا: فرمت فایل srv.txt معتبر نیست");
        }
      } else {
        setState(() => _networkStatus = "خطا در واکشی اطلاعات: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _networkStatus = "خطا در ارتباط با تکست سرور اصلی");
    } finally {
      setState(() {
        _isFetching = false;
      });
    }
  }

  // ۲. منطق دکمه بررسی موجودی حساب و فراخوانی ساب سرور
  Future<void> _checkAccountBalance() async {
    final vlessId = _idController.text.trim();
    if (vlessId.isEmpty) {
      AcrylicToast.show(context, 'ابتدا آیدی VLESS را وارد کنید', icon: Icons.error_outline);
      return;
    }

    AcrylicToast.show(context, 'در حال استعلام از سرور بالانس...', icon: Icons.sync);

    try {
      final balResponse = await http.get(Uri.parse(_balUrl));
      if (balResponse.statusCode == 200) {
        final balanceServer = balResponse.body.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => "").trim();
        
        if (balanceServer.isNotEmpty) {
          final subUrl = "https://$balanceServer/sub/$vlessId";
          final subResponse = await http.get(Uri.parse(subUrl));

          if (subResponse.statusCode == 200) {
            _showBalanceDetailsDialog(subResponse.body);
          } else {
            AcrylicToast.show(context, 'خطا از سمت ساب سرور: ${subResponse.statusCode}', isError: true);
          }
        } else {
          AcrylicToast.show(context, 'فایل bal.txt خالی است', isError: true);
        }
      } else {
        AcrylicToast.show(context, 'خطا در دریافت آی‌پی بالانس', isError: true);
      }
    } catch (e) {
      AcrylicToast.show(context, 'خطا در شبکه یا مسدود بودن لینک بالانس', isError: true);
    }
  }

  void _showBalanceDetailsDialog(String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("اطلاعات حساب و موجودی", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("فهمیدم", style: TextStyle(fontSize: 16)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnNotifier>();
    
    // هماهنگ‌سازی متن وضعیت با ناتیفایر اصلی پروژه در صورت تغییرات پس‌زمینه
    String displayStatus = _networkStatus;
    if (vpn.status == VpnStatus.connected && !_isFetching) {
      displayStatus = "وضعیت: متصل";
    } else if (vpn.status == VpnStatus.connecting) {
      displayStatus = "در حال اتصال…";
    } else if (vpn.status == VpnStatus.disconnected && displayStatus.startsWith("متصل")) {
      displayStatus = "وضعیت: قطع شده";
    }

    final bool isVpnActive = vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RSFly Client 🚀',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // بخش بالایی: دریافت آیدی و کنترلر کانکشن
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          labelText: 'VLESS ID / UUID',
                          hintText: 'آیدی اشتراک خود را وارد کنید',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isFetching ? null : () => _handleVpnToggle(vpn),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isVpnActive ? Colors.redAccent : Colors.tealAccent[700],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isFetching
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  isVpnActive ? "Stop Connection" : "Start VPN",
                                  style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // بخش میانی: نمایش زنده وضعیت و ترافیک مصرفی از طریق کانال نیتیو پروژه
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        displayStatus,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      if (vpn.status == VpnStatus.connected) ...[
                        const SizedBox(height: 12),
                        Text(
                          '▲ Up: ${(vpn.uploadBytes / 1024 / 1024).toStringAsFixed(2)} MB  |  ▼ Down: ${(vpn.downloadBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ]
                    ],
                  ),
                ),
              ),

              // بخش پایینی: دکمه بررسی موجودی حساب متصل به ساب‌سرور
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: _checkAccountBalance,
                  icon: const Icon(Icons.account_balance_wallet_rounded),
                  label: const Text("Check Balance", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
