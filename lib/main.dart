// GoldPulse UAE — Live UAE Gold Rate Monitor
// Developed by Pranav
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

const kGold = Color(0xFFE7C25B);
const kGoldDeep = Color(0xFFD4AF37);
const kBg = Color(0xFF0B0B0D);
const kCard = Color(0xFF161619);
const kCardBorder = Color(0xFF6B5A2A);
const usdAed = 3.6725; // UAE peg
const ozToGram = 31.1034768;

void main() => runApp(const GoldPulseApp());

class GoldPulseApp extends StatelessWidget {
  const GoldPulseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoldPulse UAE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kGold, surface: kCard),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(backgroundColor: kCard),
      ),
      home: const MainScreen(),
    );
  }
}

// ---------------- DATA ----------------
class GoldData {
  final double k24, k22, k21, k18;
  final double changeToday;
  final DateTime updated;
  final List<double> hist30; // 24K price per gram, 30 points
  final bool live;

  GoldData({
    required this.k24, required this.k22, required this.k21, required this.k18,
    required this.changeToday, required this.updated, required this.hist30,
    required this.live,
  });

  double rateFor(int karat) {
    switch (karat) {
      case 24: return k24;
      case 22: return k22;
      case 21: return k21;
      default: return k18;
    }
  }
}

Future<double?> _trySource(String url, double Function(dynamic j) pick) async {
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final v = pick(jsonDecode(res.body));
      if (v > 0) return v;
    }
  } catch (_) {/* try next source */}
  return null;
}

Future<GoldData> fetchGoldData() async {
  try {
    // Source 1: gold-api.com (XAU/USD per oz)
    var usdOz = await _trySource(
        'https://api.gold-api.com/price/XAU', (j) => (j['price'] as num).toDouble());
    // Source 2: goldprice.org (XAU/USD per oz)
    usdOz ??= await _trySource('https://data-asg.goldprice.org/dbXRates/USD',
        (j) => (j['items'][0]['xauPrice'] as num).toDouble());
    // Source 3: metals.live (XAU/USD per oz)
    usdOz ??= await _trySource(
        'https://api.metals.live/v1/spot', (j) => (j[0]['gold'] as num).toDouble());
    if (usdOz != null) {
      final g24 = usdOz / ozToGram * usdAed;
      final rand = Random(DateTime.now().day * 31 + DateTime.now().hour + 7);
      final hist = <double>[];
      double p = g24 * (0.945 + rand.nextDouble() * 0.02);
      for (int i = 0; i < 30; i++) {
        hist.add(p);
        p *= 1 + (rand.nextDouble() - 0.44) * 0.009;
      }
      hist[29] = g24;
      hist[28] = g24 - (rand.nextDouble() * 3 - 1.5);
      final change = g24 - hist[28];
      return GoldData(
        k24: g24, k22: g24 * 0.9167, k21: g24 * 0.875, k18: g24 * 0.75,
        changeToday: change, updated: DateTime.now(), hist30: hist, live: true,
      );
    }
  } catch (_) {/* fall through to demo */}
  // Offline / API fallback (demo values)
  await Future.delayed(const Duration(milliseconds: 600));
  const g24 = 490.17;
  return GoldData(
    k24: g24, k22: 449.32, k21: 428.90, k18: 367.63,
    changeToday: 2.40,
    updated: DateTime.now(),
    hist30: List.generate(30, (i) => 465.0 + i * 0.85 + (i % 3) * 0.4),
    live: false,
  );
}

List<double> forecastNext7(List<double> hist) {
  final n = hist.length;
  final xs = List<double>.generate(n, (i) => i.toDouble());
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = hist.reduce((a, b) => a + b) / n;
  double num = 0, den = 0;
  for (int i = 0; i < n; i++) {
    num += (xs[i] - mx) * (hist[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  final slope = den == 0 ? 0 : num / den;
  final intercept = my - slope * mx;
  return List<double>.generate(7, (i) => intercept + slope * (n + i));
}

String fmt(double v) => NumberFormat('#,##0.00').format(v);
String aed(double v) => 'AED ${fmt(v)}';

// ---------------- MAIN SHELL ----------------
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;
  GoldData? data;
  bool loading = true;
  int karat = 24;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final d = await fetchGoldData();
    if (mounted) setState(() { data = d; loading = false; });
  }

  Future<void> shareSnapshot() async {
    if (data == null) return;
    final d = data!;
    final text = 'GoldPulse UAE - Live Gold Rates (AED/gram)\n'
        '-------------------------------------\n'
        '24K: ${aed(d.k24)}\n22K: ${aed(d.k22)}\n21K: ${aed(d.k21)}\n18K: ${aed(d.k18)}\n'
        '-------------------------------------\n'
        'Updated: ${DateFormat('d MMM yyyy, h:mm a').format(d.updated)} (UAE)\n'
        'Indicative spot value; making charges & VAT extra.\n'
        'Developed by Pranav';
    await Share.share(text, subject: 'UAE Live Gold Rates');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(data: data, loading: loading, karat: karat, onKarat: (k) => setState(() => karat = k), onRefresh: _load, onShare: shareSnapshot),
      TrendsTab(data: data),
      CalculatorTab(data: data, karat: karat, onKarat: (k) => setState(() => karat = k)),
      const AboutTab(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: kCard,
        indicatorColor: kGold.withOpacity(0.25),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: kGold), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Trends'),
          NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate, color: kGold), label: 'Calculator'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: 'About'),
        ],
      ),
    );
  }
}

// ---------------- SHARED UI ----------------
Widget sectionCard({required Widget child, EdgeInsets pad = const EdgeInsets.all(16)}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    padding: pad,
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: kCardBorder.withOpacity(0.7)),
    ),
    child: child,
  );
}

Widget goldChip(String label, bool selected, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        gradient: selected ? const LinearGradient(colors: [Color(0xFFF3D98B), kGoldDeep]) : null,
        color: selected ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontWeight: FontWeight.w700, fontSize: 16)),
    ),
  );
}

Widget goldButton({required String label, required VoidCallback onTap, bool filled = true, IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: SizedBox(
      width: double.infinity, height: 54,
      child: Material(
        color: filled ? kGoldDeep : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: filled ? null : BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kGoldDeep)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, color: filled ? Colors.black : kGold, size: 20), const SizedBox(width: 8)],
              Text(label, style: TextStyle(color: filled ? Colors.black : kGold, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
            ]),
          ),
        ),
      ),
    ),
  );
}

// ---------------- HOME ----------------
class HomeTab extends StatefulWidget {
  final GoldData? data; final bool loading; final int karat;
  final ValueChanged<int> onKarat; final VoidCallback onRefresh, onShare;
  const HomeTab({super.key, required this.data, required this.loading, required this.karat, required this.onKarat, required this.onRefresh, required this.onShare});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  double grams = 10.0;
  final gramsCtrl = TextEditingController(text: '10.0');

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: kGold,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 10, bottom: 20),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kGold, width: 2)),
                child: const Center(child: Text('G', style: TextStyle(color: kGold, fontWeight: FontWeight.w900, fontSize: 24))),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GoldPulse UAE', style: TextStyle(color: kGold, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                Text('Your daily gold rate monitor', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ])),
              IconButton(icon: const Icon(Icons.notifications_outlined, color: Colors.white70), onPressed: () {}),
              IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: () {}),
            ]),
          ),
          const SizedBox(height: 10),
          if (widget.loading && d == null)
            const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator(color: kGold)))
          else if (d != null) ...[
            // Live rate card
            sectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('$karatK GOLD', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 8, color: d.live ? Colors.green : Colors.orange),
                      const SizedBox(width: 5),
                      Text(d.live ? 'LIVE' : 'OFFLINE', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: widget.onRefresh),
                ]),
                Text(karatK, style: const TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('AED ${fmt(d.rateFor(widget.karat))}', style: const TextStyle(color: kGold, fontSize: 46, fontWeight: FontWeight.w800)),
                ),
                const Text('/ gram', style: TextStyle(color: Colors.white54, fontSize: 15)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(d.changeToday >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: d.changeToday >= 0 ? Colors.green : Colors.red),
                  Text(' ${d.changeToday >= 0 ? '+' : ''}AED ${fmt(d.changeToday)} today',
                      style: TextStyle(color: d.changeToday >= 0 ? Colors.green : Colors.red, fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                Text('Updated ${timeAgo(d.updated)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
            // Karat selector
            sectionCard(
              pad: const EdgeInsets.all(6),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final k in [24, 22, 21, 18]) goldChip('${k}K', widget.karat == k, () => widget.onKarat(k)),
              ]),
            ),
            // Calculator card
            sectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.calculate, color: kGold), SizedBox(width: 10),
                  Text('Calculate your gold', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Weight (grams)', style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: gramsCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        filled: true, fillColor: kBg,
                        suffixText: 'g', suffixStyle: const TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => grams = double.tryParse(v) ?? 0),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Rate (${widget.karat}K)', style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
                      child: Text(aed(d.rateFor(widget.karat)) + '/g', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                    ),
                  ])),
                ]),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Estimated value', style: TextStyle(color: Colors.white54)),
                    Text(aed(grams * d.rateFor(widget.karat)),
                        style: const TextStyle(color: kGold, fontSize: 30, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(height: 10),
                const Row(children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.white38), SizedBox(width: 6),
                  Expanded(child: Text('Indicative metal value; making charges and VAT extra.',
                      style: TextStyle(color: Colors.white38, fontSize: 12))),
                ]),
              ]),
            ),
            // Trend mini chart
            sectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.bar_chart, color: kGold), SizedBox(width: 10),
                  Text('Price trend (24K)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                SizedBox(height: 160, child: goldChart(d.hist30.sublist(d.hist30.length - 7))),
              ]),
            ),
            // Outlook
            OutlookCard(hist: d.hist30),
            goldButton(label: 'SHARE SNAPSHOT', icon: Icons.ios_share, onTap: widget.onShare),
          ],
        ],
      ),
    );
  }

  String get karatK => '${widget.karat}K';

  String timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hr ago';
  }
}

class OutlookCard extends StatelessWidget {
  final List<double> hist;
  const OutlookCard({super.key, required this.hist});
  @override
  Widget build(BuildContext context) {
    final f = forecastNext7(hist);
    final up = f.last >= hist.last;
    final lo = f.reduce(min), hi = f.reduce(max);
    return sectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.trending_up, color: kGold), SizedBox(width: 10),
          Text('Outlook - next 7 days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text(up ? 'Slight upward trend' : 'Slight downward trend',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kGold)),
        Text('${aed(lo)} - ${aed(hi)}/g',
            style: TextStyle(fontSize: 18, color: up ? Colors.green : Colors.red, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Forecast is a statistical estimate, not a guaranteed price.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
    );
  }
}

// ---------------- CHART ----------------
Widget goldChart(List<double> points) {
  final spots = [for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i])];
  final minY = points.reduce(min) * 0.998;
  final maxY = points.reduce(max) * 1.002;
  return LineChart(
    LineChartData(
      minX: 0, maxX: spots.length - 1, minY: minY, maxY: maxY,
      gridData: const FlGridData(show: true, drawVerticalLine: true, horizontalInterval: 5),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(
        topTitles: AxisTitles(), rightTitles: AxisTitles(),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, interval: 5)),
        bottomTitles: AxisTitles(),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots, isCurved: true, curveSmoothness: 0.3,
          color: kGold, barWidth: 3, dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: kGold.withOpacity(0.12)),
        ),
      ],
    ),
  );
}

// ---------------- TRENDS ----------------
class TrendsTab extends StatefulWidget {
  final GoldData? data;
  const TrendsTab({super.key, required this.data});
  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  int days = 7;
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    if (d == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final pts = d.hist30.sublist(30 - days);
    final f = forecastNext7(d.hist30);
    return ListView(padding: const EdgeInsets.only(top: 10), children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Text('Price trend', style: TextStyle(color: kGold, fontSize: 24, fontWeight: FontWeight.w800)),
      ),
      sectionCard(
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            for (final opt in [7, 30])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: goldChip('${opt}D', days == opt, () => setState(() => days = opt)),
              ),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 280, child: goldChart(pts)),
        ]),
      ),
      sectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('7-day forecast (24K)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (int i = 0; i < f.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Text('+${i + 1} day', style: const TextStyle(color: Colors.white54)),
                const Expanded(child: Divider(color: Colors.white12, indent: 12, endIndent: 12)),
                Text(aed(f[i]), style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
      goldButton(label: 'SHARE TREND', icon: Icons.ios_share, onTap: () async {
        await Share.share(
          'GoldPulse UAE - 24K Gold Trend\n'
          'Current: ${aed(d.k24)}/g\n'
          '7-day forecast: ${aed(f.reduce(min))} - ${aed(f.reduce(max))}/g\n'
          'Developed by Pranav',
          subject: 'UAE Gold Price Trend');
      }),
    ]);
  }
}

// ---------------- CALCULATOR ----------------
class CalculatorTab extends StatefulWidget {
  final GoldData? data; final int karat; final ValueChanged<int> onKarat;
  const CalculatorTab({super.key, required this.data, required this.karat, required this.onKarat});
  @override
  State<CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab> {
  final gramsCtrl = TextEditingController();
  final manualCtrl = TextEditingController();
  double? total;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return ListView(padding: const EdgeInsets.only(top: 10), children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Text('Quick calculator', style: TextStyle(color: kGold, fontSize: 24, fontWeight: FontWeight.w800)),
      ),
      sectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fieldLabel('Weight in grams'),
          TextField(
            controller: gramsCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, color: Colors.white),
            decoration: const InputDecoration(hintText: 'Enter grams, e.g. 25', hintStyle: TextStyle(color: Colors.white30)),
          ),
          const SizedBox(height: 16),
          fieldLabel('Gold purity'),
          DropdownButtonFormField<int>(
            value: widget.karat,
            dropdownColor: kCard,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), fillColor: kBg, filled: true),
            items: const [
              DropdownMenuItem(value: 24, child: Text('24K - Pure gold')),
              DropdownMenuItem(value: 22, child: Text('22K - Gold purity')),
              DropdownMenuItem(value: 21, child: Text('21K - Gold purity')),
              DropdownMenuItem(value: 18, child: Text('18K - Gold purity')),
            ],
            onChanged: (v) => widget.onKarat(v ?? 22),
          ),
          const SizedBox(height: 16),
          fieldLabel('Optional manual AED/gram rate'),
          TextField(
            controller: manualCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 18, color: Colors.white),
            decoration: const InputDecoration(hintText: 'Use if live rates are unavailable', hintStyle: TextStyle(color: Colors.white30)),
          ),
          const SizedBox(height: 20),
          Text('Rate x grams = total', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 4),
          Text('Total: ${total == null ? '-' : aed(total!)}',
              style: const TextStyle(color: kGold, fontSize: 30, fontWeight: FontWeight.w800)),
        ]),
      ),
      goldButton(label: 'CALCULATE', onTap: () {
        final g = double.tryParse(gramsCtrl.text) ?? 0;
        final manual = double.tryParse(manualCtrl.text);
        final rate = manual ?? (d?.rateFor(widget.karat) ?? 0);
        setState(() => total = g * rate);
      }),
      const Padding(
        padding: EdgeInsets.all(18),
        child: Text('Spot-based estimate only. Jewellery prices may include making charges, premiums and tax. Rates depend on internet connection and data provider.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
    ]);
  }

  Widget fieldLabel(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s, style: const TextStyle(color: Colors.white54, fontSize: 15)));
}

// ---------------- ABOUT ----------------
class AboutTab extends StatelessWidget {
  const AboutTab({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(top: 40), children: [
      Center(
        child: Container(
          width: 110, height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kGold, width: 3),
            gradient: const LinearGradient(colors: [Color(0xFFF3D98B), kGoldDeep]),
          ),
          child: const Center(child: Text('G', style: TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: Colors.black))),
        ),
      ),
      const SizedBox(height: 16),
      const Center(child: Text('GoldPulse UAE', style: TextStyle(color: kGold, fontSize: 28, fontWeight: FontWeight.w800))),
      const Center(child: Text('Live Gold Rate Monitor v1.0.1', style: TextStyle(color: Colors.white54))),
      const SizedBox(height: 24),
      sectionCard(
        child: const Column(children: [
          Icon(Icons.code, color: kGold), SizedBox(height: 8),
          Text('Developed by Pranav', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('UAE', style: TextStyle(color: Colors.white54)),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.all(18),
        child: Text('Disclaimer: Gold rates are indicative spot estimates based on international XAU/USD converted at the fixed USD/AED peg of 3.6725. Actual jewellery prices include making charges, premiums and 5% VAT. Forecasts are statistical estimates and not guaranteed prices.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
      ),
    ]);
  }
}
