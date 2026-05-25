import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// توجه: این پکیج‌ها در پروژه اصلی برای کنترل وی‌پی‌ان استفاده می‌شوند
import 'package:asteriaray/services/vpn_service.dart'; 
import 'package:asteriaray/models/server_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _idController = TextEditingController();
  bool _isConnected = false;
  bool _isLoading = false;
  String _statusMessage = "وضعیت: قطع شده";

  // آدرس سرورهای شما
  final String _srvUrl = "http://srv.rsfly.pro/srv.txt";
  final String _balUrl = "http://srv.rsfly.pro/bal.txt";

  // ۱. منطق دکمه Start / Stop
  Future<void> _toggleVpn() async {
    final vlessId = _idController.text.trim();
    if (vlessId.isEmpty) {
      _showSnackBar("لطفاً ابتدا آیدی VLESS را وارد کنید");
      return;
    }

    if (_isConnected) {
      // قطع اتصال
      setState(() {
        _isLoading = true;
      });
      try {
        await VpnService.stopVpn(); // متد فرضی قطع اتصال در پروژه
        setState(() {
          _isConnected = false;
          _statusMessage = "وضعیت: قطع شده";
        });
      } catch (e) {
        _showSnackBar("خطا در قطع اتصال");
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // شروع اتصال و دریافت آی‌پی
    setState(() {
      _isLoading = true;
      _statusMessage = "در حال دریافت لیست سرورها...";
    });

    try {
      final response = await http.get(Uri.parse(_srvUrl));
      if (response.statusCode == 200) {
        final serverLine = response.body.split('\n').firstWhere((line) => line.trim().isNotEmpty);
        if (serverLine.contains(':')) {
          final parts = serverLine.split(':');
          final ip = parts[0].trim();
          final port = int.parse(parts[1].trim());

          // ساخت کانفیگ به فرمت استاندارد Xray/Vless برای پاس دادن به هسته برنامه
          // نکته: نام این متدها بسته به ساختار دقیق AsteriaRay ممکن است کمی متفاوت باشد 
          // اما روال کلی ریختن کانفیگ در هسته به این صورت است:
          String vlessUri = "vless://$vlessId@$ip:$port?encryption=none&security=none&type=ws";
          
          await VpnService.startVpn(vlessUri); 

          setState(() {
            _isConnected = true;
            _statusMessage = "متصل به سرور: $ip";
          });
        } else {
          setState(() => _statusMessage = "فرمت فایل srv.txt اشتباه است");
        }
      } else {
        setState(() => _statusMessage = "خطا در خواندن فایل سرور: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _statusMessage = "خطا در شبکه یا سرور");
      _showSnackBar(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ۲. منطق دکمه Check Balance (اتصال به ساب و خواندن موجودی)
  Future<void> _checkBalance() async {
    final vlessId = _idController.text.trim();
    if (vlessId.isEmpty) {
      _showSnackBar("ابتدا آیدی VLESS را وارد کنید");
      return;
    }

    setState(() {
      _statusMessage = "در حال بررسی موجودی...";
    });

    try {
      // خواندن سرور بالانس
      final balResponse = await http.get(Uri.parse(_balUrl));
      if (balResponse.statusCode == 200) {
        final balanceServer = balResponse.body.split('\n').firstWhere((line) => line.trim().isNotEmpty).trim();
        
        // درخواست به لینک ساب‌اسکریپشن اکانت کاربر
        final subUrl = "https://$balanceServer/sub/$vlessId";
        final subResponse = await http.get(Uri.parse(subUrl));

        if (subResponse.statusCode == 200) {
          _showBalanceDialog(subResponse.body);
          setState(() {
            _statusMessage = _isConnected ? "متصل" : "قطع شده";
          });
        } else {
          _showSnackBar("خطا از سمت سرور ساب: ${subResponse.statusCode}");
        }
      } else {
        _showSnackBar("خطا در خواندن فایل بالانس");
      }
    } catch (e) {
      _showSnackBar("خطا در ارتباط با سرور بالانس");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, textDirection: TextDirection.rtl)));
  }

  void _showBalanceDialog(String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("اطلاعات موجودی اکانت", textAlign: TextAlign.center),
        content: Text(content, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("تایید"),
          )
        ],
      ),
    );
  }

  // ۳. رابط کاربری (UI) طبق طرح مدنظر شما
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VPN Client"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // بخش بالایی صفحه: آیدی و دکمه استارت
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'VLESS ID (UUID)',
                          hintText: 'آیدی اختصاصی خود را وارد کنید',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _toggleVpn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isConnected ? Colors.red : Colors.green,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  _isConnected ? "Stop" : "Start",
                                  style: const TextStyle(fontSize: 18, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // بخش وسط صفحه: نمایش وضعیت فعلی
              Expanded(
                child: Center(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              // بخش پایینی صفحه: دکمه بررسی موجودی
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _checkBalance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    "Check Balance",
                    style: TextStyle(fontSize: 18, color: Colors.white),
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
