import 'api_client.dart';
import 'mock_fixtures.dart';
import 'models.dart';
import 'models_engage.dart';

/// In-memory back-office for API_MODE=mock: mirrors the rules of services/api-go (handlers_partner/admin/staff.go)
/// so the portals can be developed and demoed without a backend. The server remains the source of truth for RBAC.
/// Limitation: the traveler catalog of the mock client is static, so listing edits are visible in the portals only.
class MockPortal {
  MockPortal(this._now) {
    final now = _now();
    for (final l in kMockListings.take(12)) {
      _listings.add({
        'id': l['id'],
        'name': l['name'],
        'type': l['type'],
        'location': l['location'],
        'destinationId': l['destinationId'],
        'priceFrom': l['priceFrom'] ?? 1000,
        'description': l['description'] ?? '',
        'amenities': List<Object?>.of((l['amenities'] as List?) ?? const []),
        'mapQuery': l['mapQuery'] ?? '',
        'imageUrl': '',
        'status': 'published',
        'partnerId': (l['id'] as int) <= 4 ? 1 : 0,
      });
    }
    _users.addAll([
      _user(1, 'demo@tep.dev', 'สวัสดี อนันต์', 'traveler', now),
      _user(2, 'm_nok@members.tep.invalid', 'นก ใจดี', 'traveler', now),
      _user(3, 'm_ton@members.tep.invalid', 'ต้น สายเที่ยว', 'traveler', now),
      _user(4, 'm_fah@members.tep.invalid', 'ฟ้า ใสใจ', 'traveler', now),
      _user(5, 'm_pim@members.tep.invalid', 'พิม กินเก่ง', 'traveler', now),
      _user(6, 'admin@tep.dev', 'แอดมิน ระบบ', 'admin', now),
      _user(7, 'staff@tep.dev', 'สมชาย ซัพพอร์ต', 'staff', now),
      _user(8, 'partner@tep.dev', 'วิภา อันดามัน', 'partner', now),
    ]);
    _partners.addAll([
      {'id': 1, 'userId': 8, 'businessName': 'Andaman Partner Co.', 'contactPhone': '076-000-000', 'description': 'โรงแรมและกิจกรรมฝั่งอันดามัน', 'status': 'approved', 'commissionRate': 12.0, 'decisionNote': '', 'createdAt': now.subtract(const Duration(days: 30)).toIso8601String()},
      {'id': 2, 'userId': 4, 'businessName': 'Fah Local Tours', 'contactPhone': '081-000-0000', 'description': 'ทัวร์ท้องถิ่นกระบี่', 'status': 'pending', 'commissionRate': 12.0, 'decisionNote': '', 'createdAt': now.subtract(const Duration(hours: 6)).toIso8601String()},
    ]);
    _bookings.addAll([
      _booking(1, 2, 1, 'confirmed', now.subtract(const Duration(hours: 3))),
      _booking(2, 3, 2, 'completed', now.subtract(const Duration(hours: 30))),
      _booking(3, 2, 3, 'pending_payment', now.subtract(const Duration(hours: 1))),
    ]);
    (_bookings[1]['checks'] as List).add({'id': 1, 'staffName': 'สมชาย ซ.', 'result': 'verified', 'note': 'ตรวจสอบการชำระเงินแล้ว', 'createdAt': now.subtract(const Duration(hours: 26)).toIso8601String()});
    _nextCheck = 2;
    _tickets.addAll([
      _ticket(1, 5, 'สอบถามการยกเลิกการจอง', 'ต้องการยกเลิกการจองโรงแรมที่ภูเก็ต ทำอย่างไรคะ', 'open', now.subtract(const Duration(hours: 2))),
      _ticket(2, 2, 'คูปองใช้ไม่ได้', 'ใส่โค้ด WELCOME10 แล้วระบบแจ้งว่าไม่ผ่าน', 'answered', now.subtract(const Duration(hours: 30))),
      _ticket(3, 3, 'ขอใบกำกับภาษี', 'ขอใบกำกับภาษีสำหรับการจองที่ผ่านมา', 'resolved', now.subtract(const Duration(hours: 72))),
    ]);
    (_tickets[1]['replies'] as List).add(_reply(1, 'staff', 'สมชาย ซ.', 'ทีมงานได้รับเรื่องแล้ว กำลังตรวจสอบให้ค่ะ', now.subtract(const Duration(hours: 29))));
    (_tickets[2]['replies'] as List).add(_reply(2, 'staff', 'สมชาย ซ.', 'ส่งใบกำกับภาษีให้ทางอีเมลแล้วค่ะ', now.subtract(const Duration(hours: 71))));
    _nextReply = 3;
    _nextTicket = 4;
    _coupons.addAll([
      {'code': 'WELCOME10', 'title': 'ส่วนลดต้อนรับ 10%', 'detail': 'ขั้นต่ำ 1,000 บาท', 'percentOff': 10, 'minSpend': 1000.0, 'maxDiscount': 500.0, 'expiresOn': '', 'granted': 3, 'expired': false},
      {'code': 'PHUKET200', 'title': 'ลด 200 บาท เที่ยวภูเก็ต', 'detail': 'เฉพาะรายการในภูเก็ต', 'percentOff': 0, 'minSpend': 1500.0, 'maxDiscount': 200.0, 'expiresOn': '2099-12-31', 'granted': 0, 'expired': false},
      {'code': 'OLDDEAL', 'title': 'โปรโมชันหมดอายุ', 'detail': '', 'percentOff': 5, 'minSpend': 0.0, 'maxDiscount': 100.0, 'expiresOn': '2025-01-01', 'granted': 0, 'expired': true},
    ]);
    for (var i = 0; i < kMockFaqs.length; i++) {
      _faqs.add({'id': kMockFaqs[i]['id'], 'question': kMockFaqs[i]['question'], 'answer': kMockFaqs[i]['answer'], 'sortNo': i});
    }
    _nextFaq = kMockFaqs.length + 1;
    for (final d in kMockDestinations) {
      _dests.add(Map<String, Object?>.of(d));
    }
    _nextDest = kMockDestinations.length + 1;
    _reports.addAll([
      {'postId': 1, 'postText': 'โฆษณาขายของ ติดต่อไลน์ด่วนที่นี่เลย', 'author': 'm_nok', 'reports': 3, 'reasons': ['spam', 'spam', 'spam'], 'lastReportAt': now.subtract(const Duration(hours: 2)).toIso8601String()},
      {'postId': 2, 'postText': 'ข้อมูลร้านอาหารที่อาจไม่ถูกต้อง', 'author': 'm_ton', 'reports': 1, 'reasons': ['misinformation'], 'lastReportAt': now.subtract(const Duration(hours: 9)).toIso8601String()},
    ]);
  }

  final DateTime Function() _now;
  final List<Json> _listings = [];
  final List<Json> _users = [];
  final List<Json> _partners = [];
  final List<Json> _bookings = [];
  final List<Json> _tickets = [];
  final List<Json> _audits = [];
  int _nextListing = 13, _nextCheck = 1, _nextReply = 1, _nextTicket = 1, _nextAudit = 1, _nextPartner = 3;

  // admin content (coupons, FAQs, destinations, moderation queue, platform settings)
  final List<Json> _coupons = [];
  final List<Json> _faqs = [];
  final List<Json> _dests = [];
  final List<Json> _reports = [];
  final Map<String, String> _settings = {'service_fee_percent': '3', 'maintenance_banner': '', 'support_email': ''};
  int _nextFaq = 1, _nextDest = 1;

  // ---------- seeds ----------
  Json _user(int id, String email, String name, String role, DateTime now) =>
      {'id': id, 'handle': 'm_$id', 'email': email, 'name': name, 'role': role, 'status': 'active', 'createdAt': now.subtract(Duration(days: 40 - id)).toIso8601String()};

  Json _booking(int id, int userId, int listingId, String status, DateTime date) {
    final l = _listings.firstWhere((e) => e['id'] == listingId);
    final price = (l['priceFrom'] as num).toDouble();
    final fee = _r2(price * 0.03);
    final u = _users.isEmpty ? null : _users.where((e) => e['id'] == userId).firstOrNull;
    return {
      'id': id,
      'bookingNumber': 'TEP-${date.year % 100}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-${id.toString().padLeft(5, '0')}',
      'type': l['type'],
      'title': l['name'],
      'subtitle': l['location'],
      'status': status,
      'date': date.toIso8601String(),
      'guests': 2,
      'userId': userId,
      'travelerName': u?['name'] ?? '',
      'travelerEmail': u?['email'] ?? '',
      'subtotal': price,
      'serviceFee': fee,
      'amount': _r2(price + fee),
      'cancelReason': '',
      'lines': [
        {'listingId': listingId, 'quantity': 1, 'unitPrice': price}
      ],
      'checks': <Object?>[],
    };
  }

  Json _ticket(int id, int userId, String subject, String message, String status, DateTime at) =>
      {'id': id, 'userId': userId, 'subject': subject, 'message': message, 'status': status, 'createdAt': at.toIso8601String(), 'replies': <Object?>[], 'firstRepliedAt': null};

  Json _reply(int id, String role, String name, String message, DateTime at) =>
      {'id': id, 'authorRole': role, 'authorName': name, 'message': message, 'createdAt': at.toIso8601String()};

  // ---------- helpers ----------
  double _r2(double x) => (x * 100).roundToDouble() / 100;

  ApiException _err(int status, String code, String title, [String? detail]) => ApiException(status: status, code: code, title: title, detail: detail);
  ApiException _forbidden(String d) => _err(403, 'AUTH_FORBIDDEN', 'Forbidden', d);
  ApiException _notFound() => _err(404, 'NOT_FOUND', 'Not Found', 'resource not found');
  ApiException _conflict(String d) => _err(409, 'CONFLICT', 'Conflict', d);
  ApiException _inv(String field, String msg) =>
      ApiException(status: 422, code: 'VALIDATION_FAILED', title: 'Validation failed', errors: [FieldError(field, msg)]);

  void _need(UserProfile u, List<String> roles) {
    final role = _users.where((e) => e['id'] == u.id).firstOrNull?['role'] as String? ?? u.role;
    if (!roles.contains(role)) throw _forbidden('this area requires role ${roles.join(' or ')}');
  }

  Json? _partnerOf(int userId) => _partners.where((p) => p['userId'] == userId).firstOrNull;

  Json _myPartner(UserProfile u) {
    _need(u, ['partner']);
    final p = _partnerOf(u.id);
    if (p == null) throw _forbidden('no partner profile');
    if (p['status'] != 'approved') throw _forbidden('partner account is ${p['status']}');
    return p;
  }

  Json _find(List<Json> l, int id) {
    final r = l.where((e) => e['id'] == id).firstOrNull;
    if (r == null) throw _notFound();
    return r;
  }

  Json _pageOf(List<Json> all, Map<String, String?> q) {
    final limit = int.tryParse(q['limit'] ?? '') ?? 20;
    final offset = int.tryParse(q['offset'] ?? '') ?? 0;
    if (limit < 1 || limit > 100) throw _inv('limit', 'must be 1..100');
    if (offset < 0) throw _inv('offset', 'must be >= 0');
    final end = (offset + limit) > all.length ? all.length : offset + limit;
    final items = offset >= all.length ? <Json>[] : all.sublist(offset, end);
    return {'items': items, 'total': all.length, 'offset': offset, 'limit': limit};
  }

  bool _has(Json m, String field, String? q) => q == null || q.isEmpty || '${m[field]}'.toLowerCase().contains(q.toLowerCase());

  void _audit(UserProfile u, String action, String entity, int id, [Json? meta]) {
    final name = _users.where((e) => e['id'] == u.id).firstOrNull?['name'] ?? u.fullName;
    _audits.insert(0, {'id': _nextAudit++, 'actorId': u.id, 'actorName': name, 'action': action, 'entity': entity, 'entityId': '$id', 'meta': meta ?? <String, Object?>{}, 'createdAt': _now().toIso8601String()});
  }

  Set<int> _ownIds(int partnerId) => {for (final l in _listings) if (l['partnerId'] == partnerId) l['id'] as int};

  double _share(Json b, Set<int> own) {
    var g = 0.0;
    for (final ln in (b['lines'] as List).cast<Json>()) {
      if (own.contains(ln['listingId'])) g += (ln['quantity'] as int) * (ln['unitPrice'] as num).toDouble();
    }
    return _r2(g);
  }

  bool _allMine(Json b, Set<int> own) {
    final lines = (b['lines'] as List).cast<Json>();
    return lines.isNotEmpty && lines.every((ln) => own.contains(ln['listingId']));
  }

  bool _touches(Json b, Set<int> own) => (b['lines'] as List).cast<Json>().any((ln) => own.contains(ln['listingId']));

  // ---------- traveler side ----------
  List<SupportTicket> ticketsOf(int userId) =>
      _tickets.where((t) => t['userId'] == userId).map((t) => SupportTicket.fromJson(_ticketOut(t))).toList().reversed.toList();

  SupportTicket addTicket(UserProfile u, String subject, String message) {
    final t = _ticket(_nextTicket++, u.id, subject, message, 'open', _now());
    _tickets.add(t);
    return SupportTicket.fromJson(_ticketOut(t));
  }

  Json _ticketOut(Json t) => {
        'id': t['id'],
        'subject': t['subject'],
        'message': t['message'],
        'status': t['status'],
        'createdAt': t['createdAt'],
        'replies': List<Object?>.of(t['replies'] as List),
      };

  // ---------- dispatcher ----------
  Json call(String method, String path, {required UserProfile user, Map<String, String?> query = const {}, Object? body}) {
    final ids = <int>[];
    final norm = path.replaceAllMapped(RegExp(r'/(\d+)'), (m) {
      ids.add(int.parse(m[1]!));
      return '/{}';
    });
    final b = body is Map ? body.cast<String, Object?>() : <String, Object?>{};
    // admin resources keyed by a non-numeric id (coupon code, setting key)
    final couponM = RegExp(r'^/admin/v1/coupons/([A-Za-z0-9_-]+)$').firstMatch(path);
    if (couponM != null) {
      _need(user, ['admin']);
      return _aCouponWrite(user, method, couponM[1]!.toUpperCase(), b);
    }
    final settingM = RegExp(r'^/admin/v1/settings/([a-z_]+)$').firstMatch(path);
    if (settingM != null && method == 'PUT') {
      _need(user, ['admin']);
      return _aPutSetting(user, settingM[1]!, b);
    }
    switch ('$method $norm') {
      // traveler
      case 'POST /v1/partners/apply':
        return _apply(user, b);
      case 'GET /v1/partners/me':
        return _partnerView(_partnerOf(user.id) ?? (throw _notFound()), false);
      case 'POST /v1/support/tickets/{}/replies':
        return _travelerReply(user, ids[0], b);
      // partner
      case 'GET /partner/v1/dashboard':
        return _pDashboard(_myPartner(user));
      case 'GET /partner/v1/profile':
        return _partnerView(_myPartner(user), false);
      case 'PATCH /partner/v1/profile':
        return _pProfile(user, _myPartner(user), b);
      case 'GET /partner/v1/listings':
        return _pListings(_myPartner(user), query);
      case 'POST /partner/v1/listings':
        return _pSaveListing(user, _myPartner(user), null, b);
      case 'GET /partner/v1/listings/{}':
        return _ownListing(_myPartner(user), ids[0]);
      case 'PATCH /partner/v1/listings/{}':
        return _pSaveListing(user, _myPartner(user), ids[0], b);
      case 'GET /partner/v1/bookings':
        return _pBookings(_myPartner(user), query);
      case 'GET /partner/v1/bookings/{}':
        return _pBookingGet(_myPartner(user), ids[0]);
      case 'POST /partner/v1/bookings/{}/complete':
        return _pAct(user, _myPartner(user), ids[0], 'complete', b);
      case 'POST /partner/v1/bookings/{}/reject':
        return _pAct(user, _myPartner(user), ids[0], 'reject', b);
      case 'GET /partner/v1/earnings':
        return _earnings(_myPartner(user));
      // admin
      case 'GET /admin/v1/dashboard':
        _need(user, ['admin']);
        return _aDashboard();
      case 'GET /admin/v1/users':
        _need(user, ['admin']);
        return _aUsers(query);
      case 'GET /admin/v1/users/{}':
        _need(user, ['admin']);
        return _find(_users, ids[0]);
      case 'PATCH /admin/v1/users/{}':
        _need(user, ['admin']);
        return _aPatchUser(user, ids[0], b);
      case 'GET /admin/v1/partners':
        _need(user, ['admin']);
        return _aPartners(query);
      case 'GET /admin/v1/partners/{}':
        _need(user, ['admin']);
        return _partnerView(_find(_partners, ids[0]), true);
      case 'PATCH /admin/v1/partners/{}':
        _need(user, ['admin']);
        return _aPatchPartner(user, ids[0], b);
      case 'GET /admin/v1/listings':
        _need(user, ['admin']);
        return _aListings(query);
      case 'PATCH /admin/v1/listings/{}':
        _need(user, ['admin']);
        return _aPatchListing(user, ids[0], b);
      case 'GET /admin/v1/audit-logs':
        _need(user, ['admin']);
        return _aAudit(query);
      case 'GET /admin/v1/system':
        _need(user, ['admin']);
        return {'version': 'mock', 'env': 'dev', 'mode': 'mock', 'serverTime': _now().toUtc().toIso8601String(), 'dependencies': {'mysql': 'disabled', 'redis': 'disabled'}};
      case 'GET /admin/v1/coupons':
        _need(user, ['admin']);
        return _pageOf(_coupons, query);
      case 'POST /admin/v1/coupons':
        _need(user, ['admin']);
        return _aCouponWrite(user, 'POST', '', b);
      case 'GET /admin/v1/faqs':
        _need(user, ['admin']);
        return _pageOf(_sortedFaqs(), query);
      case 'POST /admin/v1/faqs':
        _need(user, ['admin']);
        return _aFaqWrite(user, null, b);
      case 'PUT /admin/v1/faqs/{}':
        _need(user, ['admin']);
        return _aFaqWrite(user, ids[0], b);
      case 'DELETE /admin/v1/faqs/{}':
        _need(user, ['admin']);
        _find(_faqs, ids[0]);
        _faqs.removeWhere((f) => f['id'] == ids[0]);
        _audit(user, 'admin.faq.delete', 'faq', ids[0]);
        return <String, Object?>{};
      case 'GET /admin/v1/destinations':
        _need(user, ['admin']);
        return _pageOf(_dests, {'limit': '100'});
      case 'POST /admin/v1/destinations':
        _need(user, ['admin']);
        return _aDestWrite(user, null, b);
      case 'PUT /admin/v1/destinations/{}':
        _need(user, ['admin']);
        return _aDestWrite(user, ids[0], b);
      case 'DELETE /admin/v1/destinations/{}':
        _need(user, ['admin']);
        return _aDestDelete(user, ids[0]);
      case 'GET /admin/v1/reports':
        _need(user, ['admin']);
        return _pageOf(_reports, query);
      case 'POST /admin/v1/reports/{}/dismiss':
        _need(user, ['admin']);
        return _reportAct(user, ids[0], false, 'admin');
      case 'POST /admin/v1/reports/{}/remove':
        _need(user, ['admin']);
        return _reportAct(user, ids[0], true, 'admin');
      case 'GET /moderator/v1/dashboard':
        _need(user, ['moderator', 'admin']);
        return _modDashboard();
      case 'GET /moderator/v1/reports':
        _need(user, ['moderator', 'admin']);
        return _pageOf(_reports, query);
      case 'POST /moderator/v1/reports/{}/dismiss':
        _need(user, ['moderator', 'admin']);
        return _reportAct(user, ids[0], false, 'moderator');
      case 'POST /moderator/v1/reports/{}/remove':
        _need(user, ['moderator', 'admin']);
        return _reportAct(user, ids[0], true, 'moderator');
      case 'GET /admin/v1/payments':
        _need(user, ['admin']);
        return _aPayments(query);
      case 'GET /admin/v1/payments/summary':
        _need(user, ['admin']);
        return _aPaymentSummary();
      case 'GET /admin/v1/payments/reconciliation':
        _need(user, ['admin']);
        return {'items': <Object?>[], 'total': 0, 'balanced': true};
      case 'POST /admin/v1/payments/{}/refund':
        _need(user, ['admin']);
        return _aRefund(user, ids[0], b);
      case 'GET /admin/v1/analytics':
        _need(user, ['admin']);
        return _aAnalytics(query);
      case 'GET /admin/v1/settings':
        _need(user, ['admin']);
        return _aSettings();
      // staff
      case 'GET /staff/v1/dashboard':
        _need(user, ['staff', 'admin']);
        return _sCounters(_startOfDay(_now()));
      case 'GET /staff/v1/bookings':
        _need(user, ['staff', 'admin']);
        return _sBookings(query);
      case 'GET /staff/v1/bookings/{}':
        _need(user, ['staff', 'admin']);
        return _staffBooking(_find(_bookings, ids[0]));
      case 'POST /staff/v1/bookings/{}/check':
        _need(user, ['staff', 'admin']);
        return _sCheck(user, ids[0], b);
      case 'GET /staff/v1/tickets':
        _need(user, ['staff', 'admin']);
        return _sTickets(query);
      case 'GET /staff/v1/tickets/{}':
        _need(user, ['staff', 'admin']);
        return _staffTicket(_find(_tickets, ids[0]));
      case 'PATCH /staff/v1/tickets/{}':
        _need(user, ['staff', 'admin']);
        return _sPatchTicket(user, ids[0], b);
      case 'POST /staff/v1/tickets/{}/replies':
        _need(user, ['staff', 'admin']);
        return _sReply(user, ids[0], b);
      case 'GET /staff/v1/reports/daily':
        _need(user, ['staff', 'admin']);
        return _sReport(user, query);
    }
    throw _notFound();
  }

  // ---------- admin content ----------
  List<Json> _sortedFaqs() {
    final l = List<Json>.of(_faqs);
    l.sort((a, c) {
      final d = (a['sortNo'] as int).compareTo(c['sortNo'] as int);
      return d != 0 ? d : (a['id'] as int).compareTo(c['id'] as int);
    });
    return l;
  }

  String _text(Json b, String k) => '${b[k] ?? ''}'.trim();

  Json _aCouponWrite(UserProfile u, String method, String code, Json b) {
    final create = method == 'POST';
    final c = create ? _text(b, 'code').toUpperCase() : code;
    if (create && !RegExp(r'^[A-Z0-9_-]{3,40}$').hasMatch(c)) throw _inv('code', '3-40 characters: A-Z, 0-9, _ or -');
    final existing = _coupons.where((e) => e['code'] == c).firstOrNull;
    if (method == 'DELETE') {
      if (existing == null) throw _notFound();
      if ((existing['granted'] as int) > 0) throw _conflict('coupon is held by travelers; set an expiry date instead of deleting it');
      _coupons.remove(existing);
      _audit(u, 'admin.coupon.delete', 'coupon', 0, {'code': c});
      return <String, Object?>{};
    }
    if (method != 'POST' && method != 'PUT') throw _notFound();
    if (!create && existing == null) throw _notFound();
    final title = _text(b, 'title');
    if (title.length < 2 || title.length > 190) throw _inv('title', '2-190 characters');
    final pct = (b['percentOff'] as num?)?.toInt() ?? 0;
    if (pct < 0 || pct > 100) throw _inv('percentOff', '0..100 (0 = fixed amount)');
    final maxD = (b['maxDiscount'] as num?)?.toDouble() ?? 0.0;
    if (pct == 0 && maxD <= 0) throw _inv('maxDiscount', 'required for a fixed-amount coupon');
    final exp = _text(b, 'expiresOn');
    if (exp.isNotEmpty && DateTime.tryParse(exp) == null) throw _inv('expiresOn', 'use YYYY-MM-DD');
    if (create && existing != null) throw _conflict('coupon code already exists');
    final row = <String, Object?>{
      'code': c,
      'title': title,
      'detail': _text(b, 'detail'),
      'percentOff': pct,
      'minSpend': (b['minSpend'] as num?)?.toDouble() ?? 0.0,
      'maxDiscount': maxD,
      'expiresOn': exp,
      'granted': existing?['granted'] ?? 0,
      'expired': exp.isNotEmpty && DateTime.parse(exp).isBefore(_startOfDay(_now())),
    };
    if (create) {
      _coupons.add(row);
    } else {
      _coupons[_coupons.indexOf(existing!)] = row;
    }
    _audit(u, create ? 'admin.coupon.create' : 'admin.coupon.update', 'coupon', 0, {'code': c});
    return row;
  }

  Json _aFaqWrite(UserProfile u, int? id, Json b) {
    final q = _text(b, 'question'), a = _text(b, 'answer');
    if (q.length < 3 || q.length > 255) throw _inv('question', '3-255 characters');
    if (a.length < 3 || a.length > 2000) throw _inv('answer', '3-2000 characters');
    final cur = id == null ? null : _find(_faqs, id);
    final sortNo = (b['sortNo'] as num?)?.toInt() ?? (cur?['sortNo'] as int?) ?? (_faqs.isEmpty ? 0 : _faqs.map((f) => f['sortNo'] as int).reduce((x, y) => x > y ? x : y) + 1);
    final row = <String, Object?>{'id': id ?? _nextFaq++, 'question': q, 'answer': a, 'sortNo': sortNo};
    if (cur == null) {
      _faqs.add(row);
    } else {
      _faqs[_faqs.indexOf(cur)] = row;
    }
    _audit(u, id == null ? 'admin.faq.create' : 'admin.faq.update', 'faq', row['id'] as int);
    return row;
  }

  Json _aDestWrite(UserProfile u, int? id, Json b) {
    final slug = _text(b, 'slug').toLowerCase(), name = _text(b, 'name');
    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(slug) || slug.length < 2 || slug.length > 80) throw _inv('slug', '2-80 characters: a-z, 0-9 and single hyphens');
    if (name.length < 2 || name.length > 120) throw _inv('name', '2-120 characters');
    final cur = id == null ? null : _find(_dests, id);
    if (_dests.any((d) => d['slug'] == slug && d['id'] != id)) throw _conflict('a destination with this slug already exists');
    final row = <String, Object?>{'id': id ?? _nextDest++, 'slug': slug, 'name': name, 'subtitle': _text(b, 'subtitle'), 'gradientCss': _text(b, 'gradientCss')};
    if (cur == null) {
      _dests.add(row);
    } else {
      _dests[_dests.indexOf(cur)] = row;
    }
    _audit(u, id == null ? 'admin.destination.create' : 'admin.destination.update', 'destination', row['id'] as int, {'slug': slug});
    return row;
  }

  Json _aDestDelete(UserProfile u, int id) {
    _find(_dests, id);
    if (_listings.any((l) => l['destinationId'] == id)) throw _conflict('listings still belong to this destination; move or remove them first');
    _dests.removeWhere((d) => d['id'] == id);
    _audit(u, 'admin.destination.delete', 'destination', id);
    return <String, Object?>{};
  }

  Json _reportAct(UserProfile u, int postId, bool remove, String who) {
    final row = _reports.where((r) => r['postId'] == postId).firstOrNull;
    if (row == null) throw _notFound();
    _reports.remove(row);
    _audit(u, remove ? '$who.post.remove' : '$who.report.dismiss', 'post', postId, remove ? null : {'reports': row['reports']});
    return remove ? <String, Object?>{} : {'postId': postId, 'dismissed': row['reports']};
  }

  Json _modDashboard() {
    var open = 0;
    Json? worst;
    for (final r in _reports) {
      open += r['reports'] as int;
      if (worst == null || (r['reports'] as int) > (worst['reports'] as int)) worst = r;
    }
    return {'reportedPosts': _reports.length, 'openReports': open, 'mostReported': worst};
  }

  List<Json> _payments() {
    final out = <Json>[];
    for (final b in _bookings) {
      final st = '${b['status']}';
      if (st == 'pending_payment') continue;
      final refunded = st == 'cancelled' && b['refundAmount'] != null;
      if (st == 'cancelled' && !refunded) continue;
      out.add({
        'bookingId': b['id'],
        'bookingNumber': b['bookingNumber'],
        'traveler': b['travelerEmail'],
        'method': 'promptpay',
        'status': refunded ? 'refunded' : 'succeeded',
        'amount': b['amount'],
        'confirmedAt': b['date'],
        'bookingStatus': st,
        if (refunded) 'refundAmount': b['refundAmount'],
      });
    }
    out.sort((a, c) => '${c['confirmedAt']}'.compareTo('${a['confirmedAt']}'));
    return out;
  }

  Json _aPayments(Map<String, String?> q) {
    final status = q['status'] ?? '', method = q['method'] ?? '';
    if (status.isNotEmpty && !const ['pending', 'succeeded', 'failed', 'refunded'].contains(status)) throw _inv('status', 'must be pending, succeeded, failed or refunded');
    if (method.isNotEmpty && !const ['promptpay', 'card', 'wallet'].contains(method)) throw _inv('method', 'must be promptpay, card or wallet');
    final text = (q['q'] ?? '').toLowerCase();
    final rows = _payments().where((p) {
      if (status.isNotEmpty && p['status'] != status) return false;
      if (method.isNotEmpty && p['method'] != method) return false;
      return text.isEmpty || '${p['bookingNumber']}'.toLowerCase().contains(text) || '${p['traveler']}'.toLowerCase().contains(text);
    }).toList();
    return _pageOf(rows, q);
  }

  Json _aPaymentSummary() {
    final by = <String, List<num>>{};
    for (final p in _payments()) {
      final e = by.putIfAbsent('${p['status']}', () => [0, 0.0]);
      e[0] = e[0] + 1;
      e[1] = e[1] + (p['amount'] as num);
    }
    final keys = by.keys.toList()..sort();
    return {
      'items': [for (final k in keys) {'status': k, 'count': by[k]![0], 'amount': _r2(by[k]![1].toDouble())}],
      'netCollected': _r2((by['succeeded']?[1] ?? 0).toDouble()),
    };
  }

  Json _aRefund(UserProfile u, int bookingId, Json b) {
    final reason = _text(b, 'reason');
    if (reason.length < 3 || reason.length > 255) throw _inv('reason', '3-255 characters');
    final bk = _find(_bookings, bookingId);
    if (bk['status'] != 'confirmed') throw _conflict('only paid, not yet completed bookings can be refunded; this one is ${bk['status']}');
    bk['status'] = 'cancelled';
    bk['cancelReason'] = 'admin refund: $reason';
    bk['refundAmount'] = bk['amount'];
    _audit(u, 'admin.payment.refund', 'booking', bookingId, {'amount': bk['amount'], 'reason': reason});
    return {'bookingId': bookingId, 'bookingNumber': bk['bookingNumber'], 'status': 'cancelled', 'refundAmount': bk['amount']};
  }

  Json _aAnalytics(Map<String, String?> q) {
    final days = int.tryParse(q['days'] ?? '30');
    if (days == null || days < 1 || days > 365) throw _inv('days', 'must be 1..365');
    final today = _startOfDay(_now());
    final series = <Json>[];
    var bookings = 0, newUsers = 0;
    var revenue = 0.0;
    final byType = <String, List<num>>{};
    final byStatus = <String, int>{};
    for (var i = days - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final next = day.add(const Duration(days: 1));
      var n = 0;
      var rev = 0.0;
      for (final b in _bookings) {
        final d = DateTime.parse('${b['date']}');
        if (d.isBefore(day) || !d.isBefore(next)) continue;
        byStatus['${b['status']}'] = (byStatus['${b['status']}'] ?? 0) + 1;
        if (b['status'] == 'confirmed' || b['status'] == 'completed') {
          n++;
          rev += (b['amount'] as num).toDouble();
          final t = byType.putIfAbsent('${b['type']}', () => [0, 0.0]);
          t[0] = t[0] + 1;
          t[1] = t[1] + (b['amount'] as num);
        }
      }
      var nu = 0;
      for (final u in _users) {
        final d = DateTime.parse('${u['createdAt']}');
        if (!d.isBefore(day) && d.isBefore(next)) nu++;
      }
      bookings += n;
      revenue += rev;
      newUsers += nu;
      series.add({'date': '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}', 'bookings': n, 'revenue': _r2(rev), 'newUsers': nu});
    }
    final all = byStatus.values.fold<int>(0, (a, c) => a + c);
    return {
      'days': days,
      'series': series,
      'byType': [for (final e in byType.entries) {'type': e.key, 'bookings': e.value[0], 'revenue': _r2(e.value[1].toDouble())}],
      'byStatus': byStatus,
      'totals': {
        'bookings': bookings,
        'revenue': _r2(revenue),
        'newUsers': newUsers,
        'avgOrderValue': bookings == 0 ? 0.0 : _r2(revenue / bookings),
        'cancellationRatePct': all == 0 ? 0.0 : _r2((byStatus['cancelled'] ?? 0) * 100 / all),
      },
    };
  }

  static const _settingMeta = {
    'service_fee_percent': ('number', '3', 'ค่าธรรมเนียมบริการที่บวกในทุกการจอง (เปอร์เซ็นต์ 0-20)'),
    'maintenance_banner': ('text', '', 'ประกาศถึงผู้เดินทาง (ว่าง = ซ่อน) สูงสุด 200 ตัวอักษร'),
    'support_email': ('text', '', 'อีเมลฝ่ายช่วยเหลือที่แสดงในแอป (ว่าง = ซ่อน)'),
  };

  Json _aSettings() {
    final items = [
      for (final e in _settingMeta.entries) {'key': e.key, 'value': _settings[e.key], 'default': e.value.$2, 'type': e.value.$1, 'description': e.value.$3},
    ];
    return {'items': items, 'total': items.length, 'offset': 0, 'limit': items.length};
  }

  Json _aPutSetting(UserProfile u, String key, Json b) {
    final meta = _settingMeta[key];
    if (meta == null) throw _notFound();
    var v = _text(b, 'value');
    if (key == 'service_fee_percent') {
      final f = double.tryParse(v);
      if (f == null || f < 0 || f > 20) throw _inv('value', 'a number between 0 and 20');
      v = _r2(f).toString().replaceAll(RegExp(r'\.0$'), '');
    } else if (key == 'maintenance_banner') {
      if (v.length > 200) throw _inv('value', 'at most 200 characters');
    } else if (key == 'support_email') {
      if (v.isNotEmpty && (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v) || v.length > 120)) throw _inv('value', 'a valid e-mail address (max 120 characters)');
    }
    final old = _settings[key];
    _settings[key] = v;
    _audit(u, 'admin.setting.update', 'setting', 0, {'key': key, 'from': old, 'to': v});
    return {'key': key, 'value': v, 'default': meta.$2, 'type': meta.$1, 'description': meta.$3};
  }

  // ---------- partners ----------
  Json _partnerView(Json p, bool owner) {
    final u = _users.where((e) => e['id'] == p['userId']).firstOrNull;
    return {
      ...p,
      'listingCount': _listings.where((l) => l['partnerId'] == p['id']).length,
      if (owner) 'ownerName': u?['name'] ?? '',
      if (owner) 'ownerEmail': u?['email'] ?? '',
    };
  }

  Json _apply(UserProfile u, Json b) {
    final name = '${b['businessName'] ?? ''}'.trim();
    if (name.isEmpty || name.length > 120) throw _inv('businessName', 'required, max 120 characters');
    final role = _users.where((e) => e['id'] == u.id).firstOrNull?['role'] ?? u.role;
    if (role != 'traveler') throw _conflict('only traveler accounts can apply to become a partner');
    final old = _partnerOf(u.id);
    if (old != null) {
      if (old['status'] != 'rejected') throw _conflict('a partner application already exists (${old['status']})');
      old
        ..['businessName'] = name
        ..['contactPhone'] = '${b['contactPhone'] ?? ''}'.trim()
        ..['description'] = '${b['description'] ?? ''}'.trim()
        ..['status'] = 'pending'
        ..['decisionNote'] = '';
      return _partnerView(old, false);
    }
    final p = {
      'id': _nextPartner++,
      'userId': u.id,
      'businessName': name,
      'contactPhone': '${b['contactPhone'] ?? ''}'.trim(),
      'description': '${b['description'] ?? ''}'.trim(),
      'status': 'pending',
      'commissionRate': 12.0,
      'decisionNote': '',
      'createdAt': _now().toIso8601String(),
    };
    _partners.add(p);
    return _partnerView(p, false);
  }

  Json _pProfile(UserProfile u, Json p, Json b) {
    final name = (b['businessName'] ?? p['businessName']).toString().trim();
    if (name.isEmpty || name.length > 120) throw _inv('businessName', 'required, max 120 characters');
    p
      ..['businessName'] = name
      ..['contactPhone'] = (b['contactPhone'] ?? p['contactPhone']).toString().trim()
      ..['description'] = (b['description'] ?? p['description']).toString().trim();
    _audit(u, 'partner.profile.update', 'partner', p['id'] as int);
    return _partnerView(p, false);
  }

  // ---------- partner listings ----------
  Json _listingOut(Json l) => {...l, 'amenities': List<Object?>.of(l['amenities'] as List)};

  Json _pListings(Json p, Map<String, String?> q) {
    final st = q['status'];
    if (st != null && st.isNotEmpty && !const ['draft', 'published', 'archived'].contains(st)) throw _inv('status', 'invalid status');
    final items = _listings
        .where((l) => l['partnerId'] == p['id'] && (st == null || st.isEmpty || l['status'] == st) && (q['type'] == null || q['type']!.isEmpty || l['type'] == q['type']) && (_has(l, 'name', q['q']) || _has(l, 'location', q['q'])))
        .map(_listingOut)
        .toList();
    return {'items': items};
  }

  Json _ownListing(Json p, int id) {
    final l = _find(_listings, id);
    if (l['partnerId'] != p['id']) throw _notFound();
    return _listingOut(l);
  }

  Json _pSaveListing(UserProfile u, Json p, int? id, Json b) {
    final Json l = id == null
        ? {'id': 0, 'name': '', 'type': '', 'location': '', 'destinationId': 0, 'priceFrom': 0, 'description': '', 'amenities': <Object?>[], 'mapQuery': '', 'imageUrl': '', 'status': 'draft', 'partnerId': p['id']}
        : Map<String, Object?>.of(_ownListing(p, id));
    for (final k in const ['name', 'type', 'location', 'destinationId', 'priceFrom', 'description', 'amenities', 'mapQuery', 'imageUrl', 'status']) {
      if (b.containsKey(k) && b[k] != null) l[k] = b[k];
    }
    final errs = <FieldError>[];
    final name = '${l['name']}'.trim();
    if (name.isEmpty || name.length > 190) errs.add(const FieldError('name', 'required, max 190 characters'));
    if (!const ['hotel', 'restaurant', 'attraction'].contains(l['type'])) errs.add(const FieldError('type', 'must be hotel, restaurant or attraction'));
    if ('${l['location']}'.trim().isEmpty) errs.add(const FieldError('location', 'required'));
    final price = (l['priceFrom'] as num).toDouble();
    if (price <= 0 || price > 1000000) errs.add(const FieldError('priceFrom', 'must be > 0 and <= 1,000,000'));
    if ('${l['description']}'.length > 2000) errs.add(const FieldError('description', 'max 2000 characters'));
    if (!const ['draft', 'published', 'archived'].contains(l['status'])) errs.add(const FieldError('status', 'must be draft, published or archived'));
    if (!kMockDestinations.any((d) => d['id'] == l['destinationId'])) errs.add(const FieldError('destinationId', 'unknown destination'));
    if (errs.isNotEmpty) throw ApiException(status: 422, code: 'VALIDATION_FAILED', title: 'Validation failed', errors: errs);
    l['name'] = name;
    l['priceFrom'] = _r2(price);
    if (id == null) {
      l['id'] = _nextListing++;
      _listings.add(l);
    } else {
      _listings[_listings.indexWhere((e) => e['id'] == id)] = l;
    }
    _audit(u, id == null ? 'partner.listing.create' : 'partner.listing.update', 'listing', l['id'] as int, {'status': l['status']});
    return _listingOut(l);
  }

  // ---------- partner bookings & earnings ----------
  Json _pBookingView(Json p, Set<int> own, Json b) {
    final gross = _share(b, own);
    final rate = (p['commissionRate'] as num).toDouble();
    final comm = _r2(gross * rate / 100);
    final open = b['status'] == 'confirmed' || b['status'] == 'pending_payment';
    return {
      'id': b['id'],
      'bookingNumber': b['bookingNumber'],
      'type': b['type'],
      'title': b['title'],
      'status': b['status'],
      'date': b['date'],
      'guests': b['guests'],
      'travelerName': b['travelerName'],
      'gross': gross,
      'commission': comm,
      'net': _r2(gross - comm),
      'canAct': _allMine(b, own) && open,
      'cancelReason': b['cancelReason'],
    };
  }

  Json _pBookings(Json p, Map<String, String?> q) {
    final own = _ownIds(p['id'] as int);
    final st = q['status'];
    if (st != null && st.isNotEmpty && !const ['pending_payment', 'confirmed', 'completed', 'cancelled'].contains(st)) throw _inv('status', 'invalid status');
    final list = _bookings
        .where((b) => _touches(b, own) && (st == null || st.isEmpty || b['status'] == st) && (_has(b, 'bookingNumber', q['q']) || _has(b, 'title', q['q'])))
        .toList()
      ..sort((a, c) => '${c['date']}'.compareTo('${a['date']}'));
    final page = _pageOf(list, q);
    return {...page, 'items': (page['items'] as List).cast<Json>().map((b) => _pBookingView(p, own, b)).toList()};
  }

  Json _pBookingGet(Json p, int id) {
    final own = _ownIds(p['id'] as int);
    final b = _find(_bookings, id);
    if (!_touches(b, own)) throw _notFound();
    return _pBookingView(p, own, b);
  }

  Json _pAct(UserProfile u, Json p, int id, String action, Json body) {
    final own = _ownIds(p['id'] as int);
    final b = _find(_bookings, id);
    if (!_touches(b, own)) throw _notFound();
    final reason = '${body['reason'] ?? ''}'.trim();
    if (action == 'reject' && (reason.isEmpty || reason.length > 450)) throw _inv('reason', 'required, max 450 characters');
    if (!_allMine(b, own)) throw _conflict('this booking includes items of other providers; contact support to change it');
    if (action == 'complete') {
      if (b['status'] != 'confirmed') throw _conflict('only a confirmed booking can be completed (now ${b['status']})');
      b['status'] = 'completed';
    } else {
      if (b['status'] != 'pending_payment' && b['status'] != 'confirmed') throw _conflict('booking cannot be rejected in state ${b['status']}');
      b['status'] = 'cancelled';
      b['cancelReason'] = 'ผู้ให้บริการปฏิเสธ: $reason';
    }
    _audit(u, 'partner.booking.$action', 'booking', id);
    return _pBookingView(p, own, b);
  }

  Json _earnings(Json p) {
    final own = _ownIds(p['id'] as int);
    final rate = (p['commissionRate'] as num).toDouble();
    final byMonth = <String, List<double>>{};
    final list = _bookings.where((b) => _touches(b, own) && (b['status'] == 'confirmed' || b['status'] == 'completed')).toList()
      ..sort((a, c) => '${c['date']}'.compareTo('${a['date']}'));
    for (final b in list) {
      final m = '${b['date']}'.substring(0, 7);
      final e = byMonth.putIfAbsent(m, () => [0, 0]);
      e[0] += 1;
      e[1] += _share(b, own);
    }
    var g = 0.0, c = 0.0, n = 0.0;
    final months = <Json>[];
    byMonth.forEach((m, e) {
      final gross = _r2(e[1]);
      final comm = _r2(gross * rate / 100);
      months.add({'month': m, 'bookings': e[0].toInt(), 'gross': gross, 'commission': comm, 'net': _r2(gross - comm)});
      g += gross;
      c += comm;
      n += gross - comm;
    });
    return {'commissionRate': rate, 'gross': _r2(g), 'commission': _r2(c), 'net': _r2(n), 'months': months};
  }

  Json _pDashboard(Json p) {
    final own = _ownIds(p['id'] as int);
    final by = {'draft': 0, 'published': 0, 'archived': 0};
    for (final l in _listings.where((l) => l['partnerId'] == p['id'])) {
      by['${l['status']}'] = (by['${l['status']}'] ?? 0) + 1;
    }
    int count(String st) => _bookings.where((b) => _touches(b, own) && b['status'] == st).length;
    final e = _earnings(p);
    final cur = _now().toIso8601String().substring(0, 7);
    final month = (e['months'] as List).cast<Json>().where((m) => m['month'] == cur).firstOrNull ?? {'month': cur, 'bookings': 0, 'gross': 0.0, 'commission': 0.0, 'net': 0.0};
    return {
      'businessName': p['businessName'],
      'commissionRate': p['commissionRate'],
      'listings': by,
      'bookingsToComplete': count('confirmed'),
      'bookingsAwaitingPayment': count('pending_payment'),
      'thisMonth': month,
      'totalNet': e['net'],
    };
  }

  // ---------- admin ----------
  DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

  Json _aDashboard() {
    final byRole = <String, int>{};
    for (final u in _users.where((u) => u['status'] == 'active')) {
      byRole['${u['role']}'] = (byRole['${u['role']}'] ?? 0) + 1;
    }
    final partners = <String, int>{};
    for (final p in _partners) {
      partners['${p['status']}'] = (partners['${p['status']}'] ?? 0) + 1;
    }
    final since = _startOfDay(_now());
    var revenue = 0.0;
    for (final b in _bookings.where((b) => b['status'] == 'confirmed' || b['status'] == 'completed')) {
      revenue += (b['amount'] as num).toDouble();
    }
    return {
      'users': _users.length,
      'usersSuspended': _users.where((u) => u['status'] == 'suspended').length,
      'usersByRole': byRole,
      'partners': partners,
      'listingsPublished': _listings.where((l) => l['status'] == 'published').length,
      'bookingsToday': _bookings.where((b) => !DateTime.parse('${b['date']}').isBefore(since)).length,
      'bookingsTotal': _bookings.length,
      'revenue': _r2(revenue),
    };
  }

  Json _aUsers(Map<String, String?> q) {
    final role = q['role'], st = q['status'];
    if (role != null && role.isNotEmpty && !const ['traveler', 'partner', 'staff', 'moderator', 'admin'].contains(role)) throw _inv('role', 'invalid role');
    if (st != null && st.isNotEmpty && !const ['active', 'suspended', 'deleted'].contains(st)) throw _inv('status', 'invalid status');
    final list = _users
        .where((u) => (role == null || role.isEmpty || u['role'] == role) && (st == null || st.isEmpty || u['status'] == st) && (_has(u, 'name', q['q']) || _has(u, 'email', q['q'])))
        .toList();
    return _pageOf(list, q);
  }

  Json _aPatchUser(UserProfile admin, int id, Json b) {
    final role = b['role'], status = b['status'];
    if (role == null && status == null) throw _inv('body', 'role or status required');
    if (role != null && !const ['traveler', 'staff', 'moderator', 'admin'].contains(role)) {
      throw _inv('role', 'must be traveler, staff, moderator or admin (partners are managed under /admin/v1/partners)');
    }
    if (status != null && !const ['active', 'suspended'].contains(status)) throw _inv('status', 'must be active or suspended');
    final u = _find(_users, id);
    if (u['status'] == 'deleted') throw _conflict('deleted accounts cannot be changed');
    if (u['id'] == admin.id) throw _conflict('administrators cannot change their own role or status');
    final meta = <String, Object?>{};
    if (role != null && role != u['role']) {
      if (u['role'] == 'partner') throw _conflict('partner accounts are managed under /admin/v1/partners');
      meta['role'] = [u['role'], role];
      u['role'] = role;
    }
    if (status != null && status != u['status']) {
      meta['status'] = [u['status'], status];
      u['status'] = status;
    }
    if (meta.isNotEmpty) _audit(admin, 'admin.user.update', 'user', id, meta);
    return u;
  }

  Json _aPartners(Map<String, String?> q) {
    final st = q['status'];
    if (st != null && st.isNotEmpty && !const ['pending', 'approved', 'rejected', 'suspended'].contains(st)) throw _inv('status', 'invalid status');
    final list = _partners.where((p) => (st == null || st.isEmpty || p['status'] == st) && _has(p, 'businessName', q['q'])).toList().reversed.toList();
    final page = _pageOf(list, q);
    return {...page, 'items': (page['items'] as List).cast<Json>().map((p) => _partnerView(p, true)).toList()};
  }

  static const _transitions = {
    'pending': ['approved', 'rejected'],
    'approved': ['suspended'],
    'suspended': ['approved'],
    'rejected': ['approved'],
  };

  Json _aPatchPartner(UserProfile admin, int id, Json b) {
    final p = _find(_partners, id);
    final status = b['status'], note = b['decisionNote'];
    final num? rate = b['commissionRate'] as num?;
    if (status == null && rate == null && note == null) throw _inv('body', 'status, commissionRate or decisionNote required');
    if (status != null && !const ['approved', 'rejected', 'suspended'].contains(status)) throw _inv('status', 'must be approved, rejected or suspended');
    if (rate != null && (rate < 0 || rate > 50)) throw _inv('commissionRate', 'must be between 0 and 50');
    if (note != null && '$note'.length > 500) throw _inv('decisionNote', 'max 500 characters');
    final meta = <String, Object?>{};
    if (note != null) p['decisionNote'] = '$note'.trim();
    if (rate != null && _r2(rate.toDouble()) != p['commissionRate']) {
      meta['commissionRate'] = [p['commissionRate'], _r2(rate.toDouble())];
      p['commissionRate'] = _r2(rate.toDouble());
    }
    if (status != null && status != p['status']) {
      if (!(_transitions[p['status']] ?? const []).contains(status)) throw _conflict('cannot change partner from ${p['status']} to $status');
      if (status != 'approved' && '${p['decisionNote']}'.isEmpty) throw _inv('decisionNote', 'a note is required to reject or suspend');
      if (status == 'approved') {
        final owner = _find(_users, p['userId'] as int);
        if (owner['role'] != 'traveler' && owner['role'] != 'partner') throw _conflict('the owner account has role ${owner['role']} and cannot become a partner');
        owner['role'] = 'partner';
      }
      meta['status'] = [p['status'], status];
      p['status'] = status;
      p['decidedAt'] = _now().toIso8601String();
    }
    _audit(admin, 'admin.partner.update', 'partner', id, meta);
    return _partnerView(p, true);
  }

  Json _aListings(Map<String, String?> q) {
    final st = q['status'];
    if (st != null && st.isNotEmpty && !const ['draft', 'published', 'archived'].contains(st)) throw _inv('status', 'invalid status');
    final pid = int.tryParse(q['partnerId'] ?? '');
    final items = _listings
        .where((l) => (st == null || st.isEmpty || l['status'] == st) && (q['type'] == null || q['type']!.isEmpty || l['type'] == q['type']) && (pid == null || l['partnerId'] == pid) && (_has(l, 'name', q['q']) || _has(l, 'location', q['q'])))
        .map(_listingOut)
        .toList();
    return {'items': items};
  }

  Json _aPatchListing(UserProfile admin, int id, Json b) {
    final st = b['status'];
    if (st is! String || !const ['draft', 'published', 'archived'].contains(st)) throw _inv('status', 'must be draft, published or archived');
    final l = _find(_listings, id);
    final old = l['status'];
    l['status'] = st;
    _audit(admin, 'admin.listing.status', 'listing', id, {'status': [old, st]});
    return _listingOut(l);
  }

  Json _aAudit(Map<String, String?> q) {
    final a = q['action'];
    final actor = int.tryParse(q['actorId'] ?? '');
    final list = _audits.where((x) => (a == null || a.isEmpty || '${x['action']}'.startsWith(a)) && (actor == null || x['actorId'] == actor)).toList();
    return _pageOf(list, q);
  }

  // ---------- staff ----------
  Json _staffBooking(Json b) {
    final checks = List<Object?>.of(b['checks'] as List).cast<Json>().reversed.toList();
    return {
      for (final e in b.entries)
        if (e.key != 'lines' && e.key != 'userId') e.key: e.value,
      'checks': checks,
      'verification': checks.isEmpty ? 'none' : checks.first['result'],
    };
  }

  Json _sBookings(Map<String, String?> q) {
    final st = q['status'], checked = q['checked'];
    if (st != null && st.isNotEmpty && !const ['pending_payment', 'confirmed', 'completed', 'cancelled'].contains(st)) throw _inv('status', 'invalid status');
    if (checked != null && checked.isNotEmpty && checked != 'true' && checked != 'false') throw _inv('checked', 'must be true or false');
    final list = _bookings
        .where((b) =>
            (st == null || st.isEmpty || b['status'] == st) &&
            (checked == null || checked.isEmpty || (b['checks'] as List).isNotEmpty == (checked == 'true')) &&
            (_has(b, 'bookingNumber', q['q']) || _has(b, 'title', q['q'])))
        .toList()
      ..sort((a, c) => '${c['date']}'.compareTo('${a['date']}'));
    final page = _pageOf(list, q);
    return {...page, 'items': (page['items'] as List).cast<Json>().map(_staffBooking).toList()};
  }

  Json _sCheck(UserProfile u, int id, Json b) {
    final result = b['result'], note = '${b['note'] ?? ''}'.trim();
    if (result != 'verified' && result != 'flagged') throw _inv('result', 'must be verified or flagged');
    if (result == 'flagged' && note.isEmpty) throw _inv('note', 'required when flagging a booking');
    if (note.length > 500) throw _inv('note', 'max 500 characters');
    final bk = _find(_bookings, id);
    if (bk['status'] != 'confirmed' && bk['status'] != 'completed') throw _conflict('only paid bookings (confirmed or completed) are verified; this one is ${bk['status']}');
    (bk['checks'] as List).add({'id': _nextCheck++, 'staffName': _users.firstWhere((e) => e['id'] == u.id)['name'], 'result': result, 'note': note, 'createdAt': _now().toIso8601String()});
    _audit(u, 'staff.booking.check', 'booking', id, {'result': result});
    return _staffBooking(bk);
  }

  Json _staffTicket(Json t) {
    final u = _users.where((e) => e['id'] == t['userId']).firstOrNull;
    final replies = List<Object?>.of(t['replies'] as List);
    return {..._ticketOut(t), 'travelerName': u?['name'] ?? '', 'travelerEmail': u?['email'] ?? '', 'replyCount': replies.length};
  }

  Json _sTickets(Map<String, String?> q) {
    final st = q['status'];
    if (st != null && st.isNotEmpty && !const ['open', 'answered', 'resolved'].contains(st)) throw _inv('status', 'invalid status');
    final list = _tickets.where((t) => (st == null || st.isEmpty || t['status'] == st) && (_has(t, 'subject', q['q']) || _has(t, 'message', q['q']))).toList().reversed.toList();
    final page = _pageOf(list, q);
    return {...page, 'items': (page['items'] as List).cast<Json>().map(_staffTicket).toList()};
  }

  String _msg(Json b) {
    final m = '${b['message'] ?? ''}'.trim();
    if (m.isEmpty || m.length > 2000) throw _inv('message', 'required, max 2000 characters');
    return m;
  }

  Json _sReply(UserProfile u, int id, Json b) {
    final m = _msg(b);
    final t = _find(_tickets, id);
    if (t['status'] == 'resolved') throw _conflict('ticket is resolved; reopen it before replying');
    final who = _users.firstWhere((e) => e['id'] == u.id);
    (t['replies'] as List).add(_reply(_nextReply++, who['role'] == 'admin' ? 'admin' : 'staff', '${who['name']}', m, _now()));
    t['status'] = 'answered';
    t['firstRepliedAt'] ??= _now().toIso8601String();
    _audit(u, 'staff.ticket.reply', 'ticket', id);
    return _staffTicket(t);
  }

  Json _travelerReply(UserProfile u, int id, Json b) {
    final m = _msg(b);
    final t = _find(_tickets, id);
    if (t['userId'] != u.id) throw _notFound();
    (t['replies'] as List).add(_reply(_nextReply++, 'traveler', u.fullName, m, _now()));
    t['status'] = 'open';
    return _ticketOut(t);
  }

  Json _sPatchTicket(UserProfile u, int id, Json b) {
    final st = b['status'];
    if (st != 'open' && st != 'resolved') throw _inv('status', 'must be open or resolved');
    final t = _find(_tickets, id);
    if (t['status'] != st) {
      _audit(u, 'staff.ticket.status', 'ticket', id, {'status': [t['status'], st]});
      t['status'] = st;
      t['resolvedAt'] = st == 'resolved' ? _now().toIso8601String() : null;
    }
    return _staffTicket(t);
  }

  bool _onDay(Object? iso, DateTime from, DateTime to) {
    if (iso is! String) return false;
    final d = DateTime.tryParse(iso);
    return d != null && !d.isBefore(from) && d.isBefore(to);
  }

  Json _sCounters(DateTime from) {
    final to = from.add(const Duration(days: 1));
    final checks = [for (final b in _bookings) ...(b['checks'] as List).cast<Json>().where((c) => _onDay(c['createdAt'], from, to))];
    var sum = 0.0;
    var n = 0;
    for (final t in _tickets) {
      final f = t['firstRepliedAt'];
      if (f is String) {
        sum += DateTime.parse(f).difference(DateTime.parse('${t['createdAt']}')).inMinutes / 60;
        n++;
      }
    }
    final verified = checks.where((c) => c['result'] == 'verified').length;
    return {
      'openTickets': _tickets.where((t) => t['status'] == 'open').length,
      'uncheckedBookings': _bookings.where((b) => (b['status'] == 'confirmed' || b['status'] == 'completed') && (b['checks'] as List).isEmpty).length,
      'checkedToday': checks.length,
      'verifiedToday': verified,
      'flaggedToday': checks.length - verified,
      'avgFirstResponseHours': n == 0 ? 0.0 : _r2(sum / n),
    };
  }

  Json _sReport(UserProfile u, Map<String, String?> q) {
    var day = _startOfDay(_now());
    final d = q['date'];
    if (d != null && d.isNotEmpty) {
      final p = DateTime.tryParse(d);
      if (p == null || d.length != 10) throw _inv('date', 'must be YYYY-MM-DD');
      day = DateTime(p.year, p.month, p.day);
    }
    final end = day.add(const Duration(days: 1));
    final c = _sCounters(day);
    final who = _users.firstWhere((e) => e['id'] == u.id)['name'];
    final mine = [for (final b in _bookings) ...(b['checks'] as List).cast<Json>().where((x) => x['staffName'] == who && _onDay(x['createdAt'], day, end))];
    return {
      'date': '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      'timezone': 'Asia/Bangkok',
      'bookingsCreated': _bookings.where((b) => _onDay(b['date'], day, end)).length,
      'bookingsVerified': c['verifiedToday'],
      'bookingsFlagged': c['flaggedToday'],
      'myChecks': mine.length,
      'ticketsOpened': _tickets.where((t) => _onDay(t['createdAt'], day, end)).length,
      'ticketsFirstAnswered': _tickets.where((t) => _onDay(t['firstRepliedAt'], day, end)).length,
      'ticketsResolved': _tickets.where((t) => _onDay(t['resolvedAt'], day, end)).length,
    };
  }
}
