import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import '../services/vault_provider.dart';
import '../models/password_entry.dart';
import '../services/hibp_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isScanning = false;
  bool _isDisposed = false; // 🛡️ SEC PATCH: Cancellation Token
  Map<String, int> _pwnedCache = {}; 
  
  int _selectedTab = 0; 
  List<File> _breachLogs = [];
  bool _isLoadingLogs = true;

  @override
  void initState() {
    super.initState();
    _loadBreachLogs();
  }

  @override
  void dispose() {
    // 🛡️ SEC PATCH: Prevent async leaks and memory scraping
    _isDisposed = true; 
    _pwnedCache.clear();
    _breachLogs.clear();
    super.dispose();
  }

  Future<void> _loadBreachLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final breachDir = Directory('${dir.path}/vaultx_breaches');
      
      if (await breachDir.exists()) {
        final List<FileSystemEntity> entities = await breachDir.list().toList();
        final List<File> files = entities.whereType<File>().where((f) => f.path.endsWith('.jpg')).toList();
        
        files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        
        if (!_isDisposed) {
          setState(() {
            _breachLogs = files;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading breach logs: $e");
    } finally {
      if (!_isDisposed) {
        setState(() {
          _isLoadingLogs = false;
        });
      }
    }
  }

  Future<void> _deleteLog(File file) async {
    HapticFeedback.mediumImpact();
    try {
      if (await file.exists()) {
        await file.delete();
        if (!_isDisposed) _loadBreachLogs(); 
      }
    } catch (e) {
      debugPrint("Error deleting log: $e");
    }
  }

  int _calculateStrength(String pass) {
    if (pass.isEmpty) return 1;
    bool hasUpper = RegExp(r'[A-Z]').hasMatch(pass);
    bool hasLower = RegExp(r'[a-z]').hasMatch(pass);
    bool hasDigit = RegExp(r'[0-9]').hasMatch(pass);
    bool hasSym   = RegExp(r'[!@#\$&*~_=+^%().,-]').hasMatch(pass);
    int length    = pass.length;

    if (length >= 8 && hasUpper && hasSym && hasDigit) return 3; 
    if (length >= 8 && hasDigit && hasLower) return 2; 
    return 1; 
  }

  Future<void> _runDeepScan(List<PasswordCategory> categories) async {
    if (_isDisposed) return;
    setState(() => _isScanning = true);
    HapticFeedback.mediumImpact();

    Map<String, int> results = {};
    int foundLeaks = 0;

    for (var cat in categories) {
      for (var entry in cat.entries) {
        // 🛡️ SEC PATCH: Abort loop immediately if widget is killed
        if (_isDisposed) return; 
        
        int breachCount = await HIBPService.checkPassword(entry.password);
        if (breachCount > 0) {
          results[entry.id] = breachCount;
          foundLeaks++;
        }
      }
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _pwnedCache = results;
        _isScanning = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(foundLeaks > 0 ? 'Deep Scan Complete: Found $foundLeaks leaked passwords!' : 'Deep Scan Complete: No leaks found!'),
          backgroundColor: foundLeaks > 0 ? Colors.redAccent : Colors.cyanAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text('Security Center', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFF161618), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: _buildTabButton("Password Audit", 0, Icons.shield)),
                  Expanded(child: _buildTabButton("Breach Logs", 1, Icons.camera_front)),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: _selectedTab == 0 ? _buildAuditTab() : _buildBreachLogsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index, IconData icon) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedTab = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? (index == 0 ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1)) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? (index == 0 ? Colors.cyanAccent : Colors.redAccent) : Colors.white54),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: isSelected ? (index == 0 ? Colors.cyanAccent : Colors.redAccent) : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditTab() {
    final vault = Provider.of<VaultProvider>(context);
    int strongCount = 0, mediumCount = 0, weakCount = 0;
    List<Map<String, dynamic>> vulnerableAccounts = [];

    for (var cat in vault.categories) {
      for (var entry in cat.entries) {
        int strength = _calculateStrength(entry.password);
        bool isPwned = _pwnedCache.containsKey(entry.id);

        if (strength == 3 && !isPwned) {
          strongCount++;
        } else if (isPwned || strength == 1) {
          weakCount++;
          vulnerableAccounts.add({'entry': entry, 'category': cat.name, 'strength': 1, 'pwned': isPwned ? _pwnedCache[entry.id] : 0});
        } else {
          mediumCount++;
          vulnerableAccounts.add({'entry': entry, 'category': cat.name, 'strength': 2, 'pwned': 0});
        }
      }
    }

    int total = strongCount + mediumCount + weakCount;
    double strongPct = total == 0 ? 0 : (strongCount / total) * 100;

    if (total == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.pie_chart_outline, size: 80, color: Color(0xFF222225)),
            SizedBox(height: 16),
            Text('Vault is empty. Add passwords to audit.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _isScanning 
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)))
              : TextButton.icon(
                  onPressed: () => _runDeepScan(vault.categories),
                  icon: const Icon(Icons.radar, color: Colors.cyanAccent, size: 18),
                  label: const Text("Deep Scan", style: TextStyle(color: Colors.cyanAccent)),
                ),
          ],
        ),
        _buildChart(strongPct, strongCount, mediumCount, weakCount),
        _buildStatsRow(strongCount, mediumCount, weakCount),
        const Divider(color: Colors.white10, thickness: 1, indent: 24, endIndent: 24),
        _buildVulnerabilityList(vulnerableAccounts),
      ],
    );
  }

  Widget _buildBreachLogsTab() {
    if (_isLoadingLogs) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    if (_breachLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.security, size: 80, color: Color(0xFF222225)),
            SizedBox(height: 16),
            Text('No breach attempts detected.', style: TextStyle(color: Colors.grey, fontSize: 16)),
            Text('Your physical device is secure.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _breachLogs.length,
      itemBuilder: (context, index) {
        final file = _breachLogs[index];
        final filename = file.path.split('/').last;
        final rawTime = filename.replaceAll('intruder_', '').replaceAll('.jpg', '');
        final displayTime = rawTime.replaceAll('T', ' at ').replaceAll('-', ':');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Text('UNAUTHORIZED ACCESS', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _deleteLog(file),
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(file, width: 80, height: 100, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Attempted unlocking using incorrect PIN 3 times.", style: TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 16),
                          Text("TIMESTAMP", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 2),
                          Text(displayTime, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChart(double pct, int strong, int med, int weak) {
    return SizedBox(
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 4,
              centerSpaceRadius: 80,
              sections: [
                PieChartSectionData(color: Colors.cyanAccent.shade700, value: strong.toDouble(), radius: 20, title: ''),
                PieChartSectionData(color: Colors.orangeAccent, value: med.toDouble(), radius: 25, title: ''),
                PieChartSectionData(color: Colors.redAccent, value: weak.toDouble(), radius: 30, title: ''),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${pct.toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
              const Text('Secure', style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int strong, int med, int weak) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatBadge('$strong', 'Strong', Colors.cyanAccent),
          _buildStatBadge('$med', 'Medium', Colors.orangeAccent),
          _buildStatBadge('$weak', 'Risky', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildVulnerabilityList(List<Map<String, dynamic>> accounts) {
    return Expanded(
      child: accounts.isEmpty
          ? const Center(child: Text('All accounts are secure!', style: TextStyle(color: Colors.cyanAccent)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: accounts.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const Padding(padding: EdgeInsets.all(8), child: Text('ACTION REQUIRED', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)));
                
                final item = accounts[index - 1];
                final PasswordEntry entry = item['entry'];
                final int pwnedCount = item['pwned'] ?? 0;
                final bool isPwned = pwnedCount > 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161618),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isPwned ? Colors.redAccent : (item['strength'] == 1 ? Colors.redAccent.withValues(alpha: 0.3) : Colors.orangeAccent.withValues(alpha: 0.3))),
                  ),
                  child: ListTile(
                    leading: Icon(isPwned ? Icons.report_problem : Icons.warning_amber_rounded, color: isPwned ? Colors.redAccent : (item['strength'] == 1 ? Colors.redAccent : Colors.orangeAccent)),
                    title: Text(entry.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(isPwned ? 'LEAKED $pwnedCount TIMES' : 'In Folder: ${item['category']}', style: TextStyle(color: isPwned ? Colors.redAccent : Colors.white54, fontSize: 12, fontWeight: isPwned ? FontWeight.bold : FontWeight.normal)),
                    trailing: Text(isPwned ? 'PWNED' : (item['strength'] == 1 ? 'WEAK' : 'MEDIUM'), style: TextStyle(color: isPwned || item['strength'] == 1 ? Colors.redAccent : Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatBadge(String count, String label, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}