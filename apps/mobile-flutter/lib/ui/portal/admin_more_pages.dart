import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../widgets/common.dart';
import 'portal_kit.dart';

// ---- a tiny form dialog: label/value fields in, trimmed strings out (the server validates and explains) ----

class FormFieldSpec {
  const FormFieldSpec(this.key, this.label, {this.initial = '', this.multiline = false, this.number = false, this.readOnly = false});
  final String key, label, initial;
  final bool multiline, number, readOnly;
}

Future<Map<String, String>?> askForm(BuildContext context, {required String title, required List<FormFieldSpec> fields}) =>
    showDialog<Map<String, String>>(context: context, builder: (_) => _FormDialog(title: title, fields: fields));

class _FormDialog extends StatefulWidget {
  const _FormDialog({required this.title, required this.fields});
  final String title;
  final List<FormFieldSpec> fields;
  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late final Map<String, TextEditingController> _c = {for (final f in widget.fields) f.key: TextEditingController(text: f.initial)};
  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: Key('form-${f.key}'),
                  controller: _c[f.key],
                  readOnly: f.readOnly,
                  maxLines: f.multiline ? 3 : 1,
                  keyboardType: f.number ? const TextInputType.numberWithOptions(decimal: true) : null,
                  decoration: InputDecoration(labelText: f.label),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ยกเลิก')),
          TextButton(key: const Key('form-ok'), onPressed: () => Navigator.of(context).pop({for (final e in _c.entries) e.key: e.value.text.trim()}), child: const Text('บันทึก')),
        ],
      );
}

num? _num(String? v) => (v == null || v.isEmpty) ? null : num.tryParse(v);

// ---- "more" menu ----

class AdminMorePage extends StatelessWidget {
  const AdminMorePage({super.key});

  Widget _tile(BuildContext context, String key, IconData icon, String title, String subtitle, Widget Function() page) => TepCard(
        key: Key(key),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
        child: Row(children: [
          CircleAvatar(backgroundColor: TepColors.secondary, child: Icon(icon, color: TepColors.ink)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: TepColors.muted, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: TepColors.muted),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        for (final t in [
          ('more-payments', Icons.payments_rounded, 'การชำระเงิน', 'รายการ สรุปยอด กระทบยอด และคืนเงิน', () => const AdminPaymentsPage()),
          ('more-analytics', Icons.insights_rounded, 'สถิติและรายงาน', 'รายได้ การจอง และผู้ใช้ใหม่รายวัน', () => const AdminAnalyticsPage()),
          ('more-coupons', Icons.local_offer_rounded, 'คูปอง', 'สร้าง แก้ไข และลบคูปองส่วนลด', () => const AdminCouponsPage()),
          ('more-faqs', Icons.help_center_rounded, 'คำถามที่พบบ่อย', 'จัดการ FAQ ที่แสดงในแอป', () => const AdminFaqsPage()),
          ('more-destinations', Icons.place_rounded, 'จุดหมายปลายทาง', 'จัดการข้อมูลจุดหมายปลายทาง', () => const AdminDestinationsPage()),
          ('more-reports', Icons.flag_rounded, 'รายงานโพสต์ชุมชน', 'ตรวจโพสต์ที่ถูกรายงาน', () => const ModerationQueuePage(base: '/admin/v1')),
          ('more-settings', Icons.tune_rounded, 'ตั้งค่าแพลตฟอร์ม', 'ค่าธรรมเนียม ประกาศ และอีเมลซัพพอร์ต', () => const AdminSettingsPage()),
        ])
          Padding(padding: const EdgeInsets.only(bottom: 10), child: _tile(context, t.$1, t.$2, t.$3, t.$4, t.$5)),
      ]);
}

// ---- generic CRUD list page ----

class _CrudPage extends StatefulWidget {
  const _CrudPage({required this.title, required this.path, required this.addKey, required this.onAdd, required this.itemBuilder, this.searchHint, this.filters = const [], this.emptyText = 'ไม่พบข้อมูล'});
  final String title, path, addKey, emptyText;
  final String? searchHint;
  final List<ListFilter> filters;
  final Future<bool> Function(BuildContext context) onAdd;
  final Widget Function(BuildContext context, Json item, Future<void> Function() reload) itemBuilder;
  @override
  State<_CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends State<_CrudPage> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        floatingActionButton: FloatingActionButton(
          key: Key(widget.addKey),
          tooltip: 'เพิ่ม',
          onPressed: () async {
            if (await widget.onAdd(context)) setState(() => _rev++);
          },
          child: const Icon(Icons.add_rounded),
        ),
        body: PortalList(key: ValueKey(_rev), path: widget.path, searchHint: widget.searchHint, filters: widget.filters, emptyText: widget.emptyText, itemBuilder: widget.itemBuilder),
      );
}

Widget _rowActions(List<Widget> buttons) => Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, runSpacing: 8, children: buttons));

// ---- coupons ----

class AdminCouponsPage extends StatelessWidget {
  const AdminCouponsPage({super.key});

  static List<FormFieldSpec> _fields(Json? c) => [
        FormFieldSpec('code', 'รหัสคูปอง (A-Z, 0-9, _ -)', initial: str(c?['code']), readOnly: c != null),
        FormFieldSpec('title', 'ชื่อโปรโมชัน', initial: str(c?['title'])),
        FormFieldSpec('detail', 'รายละเอียด', initial: str(c?['detail'])),
        FormFieldSpec('percentOff', 'ส่วนลด % (0 = ลดเป็นจำนวนเงิน)', initial: c == null ? '10' : str(c['percentOff']), number: true),
        FormFieldSpec('minSpend', 'ยอดขั้นต่ำ (บาท)', initial: c == null ? '0' : str(c['minSpend']), number: true),
        FormFieldSpec('maxDiscount', 'ส่วนลดสูงสุด / จำนวนเงินลด (บาท)', initial: c == null ? '0' : str(c['maxDiscount']), number: true),
        FormFieldSpec('expiresOn', 'หมดอายุ (YYYY-MM-DD ว่าง = ไม่หมดอายุ)', initial: str(c?['expiresOn'])),
      ];

  static Json _body(Map<String, String> f) => {
        'code': f['code'],
        'title': f['title'],
        'detail': f['detail'],
        'percentOff': _num(f['percentOff'])?.toInt() ?? 0,
        'minSpend': _num(f['minSpend']) ?? 0,
        'maxDiscount': _num(f['maxDiscount']) ?? 0,
        'expiresOn': f['expiresOn'],
      };

  @override
  Widget build(BuildContext context) {
    final api = AppScope.apiOf(context);
    return _CrudPage(
      title: 'คูปอง',
      path: '/admin/v1/coupons',
      addKey: 'coupon-add',
      emptyText: 'ยังไม่มีคูปอง',
      onAdd: (ctx) async {
        final f = await askForm(ctx, title: 'สร้างคูปอง', fields: _fields(null));
        if (f == null || !ctx.mounted) return false;
        return act(ctx, () => api.portal('POST', '/admin/v1/coupons', body: _body(f)), ok: 'สร้างคูปองแล้ว');
      },
      itemBuilder: (context, c, reload) {
        final code = str(c['code']);
        final pct = numOf(c['percentOff']);
        return TepCard(
          key: Key('coupon-$code'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              c['expired'] == true ? const Pill('หมดอายุ', color: TepColors.danger) : const Pill('ใช้งานได้', color: TepColors.success),
            ]),
            Text(str(c['title'])),
            Text(pct > 0 ? 'ลด ${pct.toInt()}% (สูงสุด ${thb(numOf(c['maxDiscount']))})' : 'ลด ${thb(numOf(c['maxDiscount']))}', style: const TextStyle(color: TepColors.muted, fontSize: 12)),
            Text('ขั้นต่ำ ${thb(numOf(c['minSpend']))} · อยู่ในกระเป๋า ${numOf(c['granted']).toInt()} ราย${str(c['expiresOn']).isEmpty ? '' : ' · หมดอายุ ${str(c['expiresOn'])}'}', style: const TextStyle(color: TepColors.muted, fontSize: 12)),
            _rowActions([
              tileButton('แก้ไข', () async {
                final f = await askForm(context, title: 'แก้ไขคูปอง $code', fields: _fields(c));
                if (f == null || !context.mounted) return;
                if (await act(context, () => api.portal('PUT', '/admin/v1/coupons/$code', body: _body(f)), ok: 'บันทึกแล้ว')) await reload();
              }, key: Key('coupon-edit-$code'), outlined: true),
              tileButton('ลบ', () async {
                if (!await confirmDialog(context, 'ลบคูปอง $code', 'คูปองที่อยู่ในกระเป๋าผู้ใช้ลบไม่ได้ ให้ตั้งวันหมดอายุแทน')) return;
                if (!context.mounted) return;
                if (await act(context, () => api.portal('DELETE', '/admin/v1/coupons/$code'), ok: 'ลบแล้ว')) await reload();
              }, key: Key('coupon-delete-$code'), danger: true, outlined: true),
            ]),
          ]),
        );
      },
    );
  }
}

// ---- FAQs ----

class AdminFaqsPage extends StatelessWidget {
  const AdminFaqsPage({super.key});

  static List<FormFieldSpec> _fields(Json? f) => [
        FormFieldSpec('question', 'คำถาม', initial: str(f?['question']), multiline: true),
        FormFieldSpec('answer', 'คำตอบ', initial: str(f?['answer']), multiline: true),
        if (f != null) FormFieldSpec('sortNo', 'ลำดับ (น้อยขึ้นก่อน)', initial: str(f['sortNo']), number: true),
      ];

  static Json _body(Map<String, String> f) => {'question': f['question'], 'answer': f['answer'], if (_num(f['sortNo']) != null) 'sortNo': _num(f['sortNo'])!.toInt()};

  @override
  Widget build(BuildContext context) {
    final api = AppScope.apiOf(context);
    return _CrudPage(
      title: 'คำถามที่พบบ่อย',
      path: '/admin/v1/faqs',
      addKey: 'faq-add',
      searchHint: null,
      onAdd: (ctx) async {
        final f = await askForm(ctx, title: 'เพิ่มคำถาม', fields: _fields(null));
        if (f == null || !ctx.mounted) return false;
        return act(ctx, () => api.portal('POST', '/admin/v1/faqs', body: _body(f)), ok: 'เพิ่มแล้ว');
      },
      itemBuilder: (context, f, reload) {
        final id = f['id'];
        return TepCard(
          key: Key('faq-$id'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(f['question']), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(str(f['answer']), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TepColors.muted, fontSize: 12)),
            _rowActions([
              tileButton('แก้ไข', () async {
                final r = await askForm(context, title: 'แก้ไขคำถาม', fields: _fields(f));
                if (r == null || !context.mounted) return;
                if (await act(context, () => api.portal('PUT', '/admin/v1/faqs/$id', body: _body(r)), ok: 'บันทึกแล้ว')) await reload();
              }, key: Key('faq-edit-$id'), outlined: true),
              tileButton('ลบ', () async {
                if (!await confirmDialog(context, 'ลบคำถามนี้?', str(f['question']))) return;
                if (!context.mounted) return;
                if (await act(context, () => api.portal('DELETE', '/admin/v1/faqs/$id'), ok: 'ลบแล้ว')) await reload();
              }, key: Key('faq-delete-$id'), danger: true, outlined: true),
            ]),
          ]),
        );
      },
    );
  }
}

// ---- destinations ----

class AdminDestinationsPage extends StatelessWidget {
  const AdminDestinationsPage({super.key});

  static List<FormFieldSpec> _fields(Json? d) => [
        FormFieldSpec('slug', 'slug (a-z, 0-9, -)', initial: str(d?['slug'])),
        FormFieldSpec('name', 'ชื่อ', initial: str(d?['name'])),
        FormFieldSpec('subtitle', 'คำอธิบายสั้น', initial: str(d?['subtitle'])),
        FormFieldSpec('gradientCss', 'สี (linear-gradient(...))', initial: str(d?['gradientCss'])),
      ];

  static Json _body(Map<String, String> f) => {'slug': f['slug'], 'name': f['name'], 'subtitle': f['subtitle'], 'gradientCss': f['gradientCss']};

  @override
  Widget build(BuildContext context) {
    final api = AppScope.apiOf(context);
    return _CrudPage(
      title: 'จุดหมายปลายทาง',
      path: '/admin/v1/destinations',
      addKey: 'dest-add',
      onAdd: (ctx) async {
        final f = await askForm(ctx, title: 'เพิ่มจุดหมายปลายทาง', fields: _fields(null));
        if (f == null || !ctx.mounted) return false;
        return act(ctx, () => api.portal('POST', '/admin/v1/destinations', body: _body(f)), ok: 'เพิ่มแล้ว');
      },
      itemBuilder: (context, d, reload) {
        final id = d['id'];
        return TepCard(
          key: Key('dest-$id'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(str(d['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Pill(str(d['slug']), color: TepColors.primary),
            ]),
            Text(str(d['subtitle']), style: const TextStyle(color: TepColors.muted, fontSize: 12)),
            _rowActions([
              tileButton('แก้ไข', () async {
                final r = await askForm(context, title: 'แก้ไข ${str(d['name'])}', fields: _fields(d));
                if (r == null || !context.mounted) return;
                if (await act(context, () => api.portal('PUT', '/admin/v1/destinations/$id', body: _body(r)), ok: 'บันทึกแล้ว')) await reload();
              }, key: Key('dest-edit-$id'), outlined: true),
              tileButton('ลบ', () async {
                if (!await confirmDialog(context, 'ลบ ${str(d['name'])}?', 'ลบไม่ได้หากยังมีรายการสินค้าอยู่ในจุดหมายนี้')) return;
                if (!context.mounted) return;
                if (await act(context, () => api.portal('DELETE', '/admin/v1/destinations/$id'), ok: 'ลบแล้ว')) await reload();
              }, key: Key('dest-delete-$id'), danger: true, outlined: true),
            ]),
          ]),
        );
      },
    );
  }
}

// ---- moderation queue (admin and moderator portals share it) ----

class ModerationQueueBody extends StatelessWidget {
  const ModerationQueueBody({super.key, required this.base});
  final String base; // '/admin/v1' or '/moderator/v1'
  @override
  Widget build(BuildContext context) {
    final api = AppScope.apiOf(context);
    return PortalList(
      path: '$base/reports',
      emptyText: 'ไม่มีโพสต์ที่ถูกรายงาน',
      itemBuilder: (context, r, reload) {
        final id = r['postId'];
        final reasons = (r['reasons'] as List?)?.map((e) => '$e').toSet().join(', ') ?? '';
        return TepCard(
          key: Key('report-$id'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('โดย ${str(r['author'])}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Pill('${numOf(r['reports']).toInt()} รายงาน', color: TepColors.danger),
            ]),
            const SizedBox(height: 4),
            Text(str(r['postText']), maxLines: 4, overflow: TextOverflow.ellipsis),
            Text('เหตุผล: $reasons', style: const TextStyle(color: TepColors.muted, fontSize: 12)),
            _rowActions([
              tileButton('ปิดรายงาน', () async {
                if (await act(context, () => api.portal('POST', '$base/reports/$id/dismiss'), ok: 'ปิดรายงานแล้ว')) await reload();
              }, key: Key('dismiss-$id'), outlined: true),
              tileButton('ลบโพสต์', () async {
                if (!await confirmDialog(context, 'ลบโพสต์นี้?', 'โพสต์จะถูกลบออกจากชุมชนถาวร')) return;
                if (!context.mounted) return;
                if (await act(context, () => api.portal('POST', '$base/reports/$id/remove'), ok: 'ลบโพสต์แล้ว')) await reload();
              }, key: Key('remove-$id'), danger: true),
            ]),
          ]),
        );
      },
    );
  }
}

class ModerationQueuePage extends StatelessWidget {
  const ModerationQueuePage({super.key, required this.base});
  final String base;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('รายงานโพสต์ชุมชน')), body: ModerationQueueBody(base: base));
}

// ---- payments ----

const paymentStatusLabels = {'succeeded': 'สำเร็จ', 'refunded': 'คืนเงินแล้ว', 'pending': 'รอชำระ', 'failed': 'ล้มเหลว'};

class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});
  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  int _rev = 0;

  Future<void> _reconcile() async {
    final api = AppScope.apiOf(context);
    final r = await guarded<Json>(context, () => api.portal('GET', '/admin/v1/payments/reconciliation'));
    if (r == null || !mounted) return;
    final issues = jlist(r['items']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('กระทบยอดการชำระเงิน'),
        content: issues.isEmpty
            ? const Text('บัญชีตรงกัน ไม่พบรายการผิดปกติ', key: Key('reconcile-ok'))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final i in issues) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${str(i['bookingNumber'])}: ${str(i['detail'])}')),
                ]),
              ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ปิด'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('การชำระเงิน'), actions: [
        IconButton(key: const Key('reconcile'), tooltip: 'กระทบยอด', icon: const Icon(Icons.balance_rounded), onPressed: _reconcile),
      ]),
      body: Column(children: [
        AsyncBody<Json>(
          key: ValueKey('sum-$_rev'),
          load: () => api.portal('GET', '/admin/v1/payments/summary'),
          builder: (context, s, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TepCard(
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_rounded, color: TepColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('เก็บเงินสุทธิ', style: const TextStyle(color: TepColors.muted))),
                Text(thb(numOf(s['netCollected'])), key: const Key('net-collected'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: PortalList(
            key: ValueKey('list-$_rev'),
            path: '/admin/v1/payments',
            searchHint: 'ค้นหาเลขการจองหรืออีเมล',
            emptyText: 'ไม่พบรายการชำระเงิน',
            filters: const [
              ListFilter('ทั้งหมด'),
              ListFilter('สำเร็จ', {'status': 'succeeded'}),
              ListFilter('คืนเงินแล้ว', {'status': 'refunded'}),
            ],
            itemBuilder: (context, p, reload) {
              final id = p['bookingId'];
              return TepCard(
                key: Key('payment-$id'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(str(p['bookingNumber']), style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatePill(str(p['status']), paymentStatusLabels),
                  ]),
                  Text(str(p['traveler']), style: const TextStyle(color: TepColors.muted, fontSize: 12)),
                  Text('${thb(numOf(p['amount']))} · ${str(p['method'])} · ${dateOf(p['confirmedAt'])}', style: const TextStyle(fontSize: 13)),
                  if (p['bookingStatus'] == 'confirmed')
                    _rowActions([
                      tileButton('คืนเงิน', () async {
                        final reason = await askText(context, title: 'คืนเงินให้ผู้เดินทาง', label: 'เหตุผล (บังคับ)', maxLength: 255);
                        if (reason == null || !context.mounted) return;
                        if (await act(context, () => api.portal('POST', '/admin/v1/payments/$id/refund', body: {'reason': reason}), ok: 'คืนเงินเข้า Wallet แล้ว')) {
                          setState(() => _rev++);
                        }
                      }, key: Key('refund-$id'), danger: true, outlined: true),
                    ]),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---- analytics ----

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});
  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('สถิติและรายงาน')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              for (final d in const [7, 30, 90])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(key: Key('days-$d'), label: Text('$d วัน'), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
                ),
            ]),
          ),
          Expanded(
            child: PortalPage(
              key: ValueKey('analytics-$_days'),
              path: '/admin/v1/analytics',
              query: {'days': '$_days'},
              builder: (context, a) {
                final t = jmap(a['totals']);
                final series = jlist(a['series']);
                final shown = series.length > 14 ? series.sublist(series.length - 14) : series;
                final maxRev = shown.fold<num>(0, (m, e) => numOf(e['revenue']) > m ? numOf(e['revenue']) : m);
                return [
                  KpiGrid([
                    Kpi('รายได้', thb(numOf(t['revenue'])), Icons.payments_rounded),
                    Kpi('การจองที่ชำระแล้ว', '${numOf(t['bookings']).toInt()}', Icons.receipt_long_rounded),
                    Kpi('ผู้ใช้ใหม่', '${numOf(t['newUsers']).toInt()}', Icons.person_add_rounded),
                    Kpi('มูลค่าเฉลี่ย/ออเดอร์', thb(numOf(t['avgOrderValue'])), Icons.shopping_bag_rounded),
                    Kpi('อัตรายกเลิก', '${numOf(t['cancellationRatePct'])}%', Icons.cancel_rounded),
                  ]),
                  const SizedBox(height: 16),
                  const Text('รายได้รายวัน (14 วันล่าสุด)', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final p in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        SizedBox(width: 78, child: Text(str(p['date']).length >= 10 ? str(p['date']).substring(5) : str(p['date']), style: const TextStyle(fontSize: 12, color: TepColors.muted))),
                        Expanded(child: LinearProgressIndicator(value: maxRev == 0 ? 0 : (numOf(p['revenue']) / maxRev).toDouble(), minHeight: 10, borderRadius: BorderRadius.circular(5))),
                        const SizedBox(width: 8),
                        SizedBox(width: 86, child: Text(thb(numOf(p['revenue'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                      ]),
                    ),
                  const SizedBox(height: 16),
                  const Text('แยกตามประเภท', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final e in jlist(a['byType']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(str(e['type'])),
                      subtitle: Text('${numOf(e['bookings']).toInt()} การจอง'),
                      trailing: Text(thb(numOf(e['revenue'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ];
              },
            ),
          ),
        ]),
      );
}

// ---- platform settings ----

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าแพลตฟอร์ม')),
      body: PortalPage(
        key: ValueKey('settings-$_rev'),
        path: '/admin/v1/settings',
        builder: (context, d) => [
          for (final s in jlist(d['items']))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TepCard(
                key: Key('setting-${s['key']}'),
                onTap: () async {
                  final r = await askText(context, title: str(s['key']), label: str(s['description']), mandatory: false, maxLength: 200, initial: str(s['value']), keyboard: s['type'] == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text);
                  if (r == null || !context.mounted) return;
                  if (await act(context, () => api.portal('PUT', '/admin/v1/settings/${s['key']}', body: {'value': r}), ok: 'บันทึกแล้ว')) setState(() => _rev++);
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(str(s['key']), style: const TextStyle(fontWeight: FontWeight.w700))),
                    const Icon(Icons.edit_rounded, size: 18, color: TepColors.muted),
                  ]),
                  Text(str(s['value']).isEmpty ? '(ว่าง)' : str(s['value']), key: Key('setting-value-${s['key']}'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(str(s['description']), style: const TextStyle(color: TepColors.muted, fontSize: 12)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
