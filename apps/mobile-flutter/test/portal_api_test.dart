import 'package:flutter_test/flutter_test.dart';
import 'package:tep_mobile/data/api_client.dart';
import 'package:tep_mobile/data/mock_api_client.dart';
import 'package:tep_mobile/data/models.dart';

Future<MockApiClient> as_(String email) async {
  final api = MockApiClient(latency: Duration.zero, settleAfter: Duration.zero);
  await api.login(email, MockApiClient.demoPassword);
  return api;
}

Matcher status(int s) => throwsA(isA<ApiException>().having((e) => e.status, 'status', s));
List<Json> items(Json j) => (j['items'] as List).cast<Json>();

void main() {
  test('each portal rejects the other roles with 403', () async {
    final traveler = await as_('demo@tep.dev');
    final partner = await as_('partner@tep.dev');
    final staff = await as_('staff@tep.dev');
    final admin = await as_('admin@tep.dev');
    for (final path in ['/partner/v1/dashboard', '/admin/v1/dashboard', '/staff/v1/dashboard']) {
      await expectLater(traveler.portal('GET', path), status(403));
    }
    await expectLater(staff.portal('GET', '/admin/v1/users'), status(403));
    await expectLater(partner.portal('GET', '/staff/v1/tickets'), status(403));
    await expectLater(admin.portal('GET', '/partner/v1/listings'), status(403));
    expect((await admin.portal('GET', '/staff/v1/dashboard'))['openTickets'], 1); // admin may use the staff portal
  });

  test('partner manages own listings and bookings', () async {
    final api = await as_('partner@tep.dev');
    expect(items(await api.portal('GET', '/partner/v1/listings')).length, 4);
    await expectLater(api.portal('GET', '/partner/v1/listings/5'), status(404)); // someone else's
    await expectLater(api.portal('POST', '/partner/v1/listings', body: {'name': '', 'type': 'flight', 'priceFrom': -1, 'destinationId': 1}), status(422));
    final created = await api.portal('POST', '/partner/v1/listings', body: {
      'name': 'Sunset Villa', 'type': 'hotel', 'location': 'Phuket', 'destinationId': 1, 'priceFrom': 2500, 'status': 'published',
    });
    expect(created['status'], 'published');
    final patched = await api.portal('PATCH', '/partner/v1/listings/${created['id']}', body: {'status': 'archived'});
    expect(patched['status'], 'archived');

    final all = await api.portal('GET', '/partner/v1/bookings');
    expect(all['total'], 3);
    final done = await api.portal('POST', '/partner/v1/bookings/1/complete');
    expect(done['status'], 'completed');
    await expectLater(api.portal('POST', '/partner/v1/bookings/1/complete'), status(409));
    await expectLater(api.portal('POST', '/partner/v1/bookings/3/reject', body: {}), status(422));
    final rejected = await api.portal('POST', '/partner/v1/bookings/3/reject', body: {'reason': 'ห้องเต็ม'});
    expect(rejected['status'], 'cancelled');

    final e = await api.portal('GET', '/partner/v1/earnings');
    expect(e['commissionRate'], 12);
    expect((e['commission'] as num).toDouble(), closeTo((e['gross'] as num) * 0.12, 0.011));
  });

  test('admin approves an application, which promotes the owner; transitions are enforced', () async {
    final api = await as_('admin@tep.dev');
    await expectLater(api.portal('PATCH', '/admin/v1/partners/2', body: {'status': 'suspended'}), status(409));
    await expectLater(api.portal('PATCH', '/admin/v1/partners/2', body: {'status': 'rejected'}), status(422));
    await expectLater(api.portal('PATCH', '/admin/v1/partners/2', body: {'commissionRate': 60}), status(422));
    final p = await api.portal('PATCH', '/admin/v1/partners/2', body: {'status': 'approved', 'commissionRate': 10});
    expect(p['status'], 'approved');
    expect((await api.portal('GET', '/admin/v1/users/4'))['role'], 'partner');
    // users: never to partner, never self
    await expectLater(api.portal('PATCH', '/admin/v1/users/1', body: {'role': 'partner'}), status(422));
    await expectLater(api.portal('PATCH', '/admin/v1/users/6', body: {'status': 'suspended'}), status(409));
    final u = await api.portal('PATCH', '/admin/v1/users/1', body: {'role': 'moderator'});
    expect(u['role'], 'moderator');
    final audit = await api.portal('GET', '/admin/v1/audit-logs', query: {'action': 'admin.'});
    expect(audit['total'], 2);
  });

  test('staff verifies bookings and answers tickets; traveler sees the answer', () async {
    final staff = await as_('staff@tep.dev');
    await expectLater(staff.portal('POST', '/staff/v1/bookings/1/check', body: {'result': 'flagged'}), status(422));
    await expectLater(staff.portal('POST', '/staff/v1/bookings/3/check', body: {'result': 'verified'}), status(409));
    final b = await staff.portal('POST', '/staff/v1/bookings/1/check', body: {'result': 'verified'});
    expect(b['verification'], 'verified');
    expect((await staff.portal('GET', '/staff/v1/dashboard'))['uncheckedBookings'], 0);

    final t = await staff.portal('POST', '/staff/v1/tickets/1/replies', body: {'message': 'รับเรื่องแล้วค่ะ'});
    expect(t['status'], 'answered');
    final r = await staff.portal('PATCH', '/staff/v1/tickets/1', body: {'status': 'resolved'});
    expect(r['status'], 'resolved');
    await expectLater(staff.portal('POST', '/staff/v1/tickets/1/replies', body: {'message': 'x'}), status(409));
    expect((await staff.portal('GET', '/staff/v1/reports/daily'))['bookingsVerified'], 1);
  });

  test('traveler applies, ticket replies reopen the ticket', () async {
    final api = await as_('demo@tep.dev');
    await expectLater(api.portal('GET', '/v1/partners/me'), status(404));
    expect((await api.portal('POST', '/v1/partners/apply', body: {'businessName': 'Demo Tours'}))['status'], 'pending');
    await expectLater(api.portal('POST', '/v1/partners/apply', body: {'businessName': 'Again'}), status(409));
    final t = await api.createTicket(subject: 'ช่วยด้วย', message: 'ขอเลื่อนวัน');
    expect(t.status, 'open');
    final out = await api.portal('POST', '/v1/support/tickets/${t.id}/replies', body: {'message': 'วันที่ 20'});
    expect(out['status'], 'open');
    expect((await api.tickets()).first.replies.length, 1);
  });

  test('admin manages coupons, FAQs and destinations with validation and conflicts', () async {
    final api = await as_('admin@tep.dev');
    await expectLater(api.portal('POST', '/admin/v1/coupons', body: {'code': 'x', 'title': 'ทดสอบ'}), status(422));
    await expectLater(api.portal('POST', '/admin/v1/coupons', body: {'code': 'WELCOME10', 'title': 'ซ้ำ', 'percentOff': 5}), status(409));
    final c = await api.portal('POST', '/admin/v1/coupons', body: {'code': 'qa50', 'title': 'ทดสอบ 50', 'percentOff': 50, 'maxDiscount': 300});
    expect(c['code'], 'QA50');
    final up = await api.portal('PUT', '/admin/v1/coupons/QA50', body: {'title': 'ทดสอบ 50 ใหม่', 'percentOff': 40, 'maxDiscount': 300});
    expect(up['title'], 'ทดสอบ 50 ใหม่');
    await expectLater(api.portal('DELETE', '/admin/v1/coupons/WELCOME10'), status(409)); // held by travelers
    await api.portal('DELETE', '/admin/v1/coupons/QA50');
    await expectLater(api.portal('DELETE', '/admin/v1/coupons/QA50'), status(404));

    final before = (await api.portal('GET', '/admin/v1/faqs'))['total'] as int;
    final f = await api.portal('POST', '/admin/v1/faqs', body: {'question': 'ทดสอบคำถาม', 'answer': 'ทดสอบคำตอบ'});
    expect((await api.portal('GET', '/admin/v1/faqs'))['total'], before + 1);
    await api.portal('DELETE', '/admin/v1/faqs/${f['id']}');
    expect((await api.portal('GET', '/admin/v1/faqs'))['total'], before);

    await expectLater(api.portal('POST', '/admin/v1/destinations', body: {'slug': 'Bad Slug', 'name': 'ทดสอบ'}), status(422));
    await expectLater(api.portal('POST', '/admin/v1/destinations', body: {'slug': 'phuket', 'name': 'ซ้ำ'}), status(409));
    await expectLater(api.portal('DELETE', '/admin/v1/destinations/1'), status(409)); // listings still belong to it
    final d = await api.portal('POST', '/admin/v1/destinations', body: {'slug': 'qa-dest', 'name': 'ปลายทางทดสอบ'});
    await api.portal('DELETE', '/admin/v1/destinations/${d['id']}');
    final audit = await api.portal('GET', '/admin/v1/audit-logs', query: {'action': 'admin.coupon.'});
    expect(audit['total'], 3);
  });

  test('moderator portal: queue, dismiss, remove; roles are enforced', () async {
    final mod = await as_('moderator@tep.dev');
    final dash = await mod.portal('GET', '/moderator/v1/dashboard');
    expect(dash['reportedPosts'], 2);
    expect(dash['openReports'], 4);
    await expectLater(mod.portal('GET', '/admin/v1/reports'), status(403));
    await expectLater(mod.portal('GET', '/admin/v1/users'), status(403));
    await expectLater((await as_('staff@tep.dev')).portal('GET', '/moderator/v1/reports'), status(403));
    await expectLater((await as_('demo@tep.dev')).portal('GET', '/moderator/v1/dashboard'), status(403));
    final q = await mod.portal('GET', '/moderator/v1/reports');
    expect(q['total'], 2);
    expect((await mod.portal('POST', '/moderator/v1/reports/2/dismiss'))['dismissed'], 1);
    await mod.portal('POST', '/moderator/v1/reports/1/remove');
    await expectLater(mod.portal('POST', '/moderator/v1/reports/1/remove'), status(404));
    expect((await mod.portal('GET', '/moderator/v1/dashboard'))['reportedPosts'], 0);
    final admin = await as_('admin@tep.dev');
    expect((await admin.portal('GET', '/admin/v1/audit-logs', query: {'action': 'moderator.'}))['total'], 2);
  });

  test('admin payments: list, summary, reconciliation and a guarded refund', () async {
    final api = await as_('admin@tep.dev');
    await expectLater(api.portal('GET', '/admin/v1/payments', query: {'status': 'bogus'}), status(422));
    final list = await api.portal('GET', '/admin/v1/payments');
    expect(list['total'], 2); // booking 3 is still awaiting payment
    final sum = await api.portal('GET', '/admin/v1/payments/summary');
    expect((sum['netCollected'] as num) > 0, isTrue);
    expect((await api.portal('GET', '/admin/v1/payments/reconciliation'))['balanced'], true);
    await expectLater(api.portal('POST', '/admin/v1/payments/1/refund', body: {'reason': 'x'}), status(422));
    await expectLater(api.portal('POST', '/admin/v1/payments/2/refund', body: {'reason': 'ลูกค้าขอ'}), status(409)); // completed
    final r = await api.portal('POST', '/admin/v1/payments/1/refund', body: {'reason': 'บริการไม่ตรงตามที่ระบุ'});
    expect(r['status'], 'cancelled');
    await expectLater(api.portal('POST', '/admin/v1/payments/1/refund', body: {'reason': 'ซ้ำ'}), status(409));
    final refunded = await api.portal('GET', '/admin/v1/payments', query: {'status': 'refunded'});
    expect(refunded['total'], 1);
    await expectLater((await as_('staff@tep.dev')).portal('GET', '/admin/v1/payments'), status(403));
  });

  test('admin analytics and platform settings', () async {
    final api = await as_('admin@tep.dev');
    await expectLater(api.portal('GET', '/admin/v1/analytics', query: {'days': '0'}), status(422));
    final a = await api.portal('GET', '/admin/v1/analytics', query: {'days': '7'});
    expect((a['series'] as List).length, 7);
    expect((a['totals'] as Map)['bookings'], 2);
    final settings = await api.portal('GET', '/admin/v1/settings');
    expect(settings['total'], 3);
    await expectLater(api.portal('PUT', '/admin/v1/settings/service_fee_percent', body: {'value': '21'}), status(422));
    await expectLater(api.portal('PUT', '/admin/v1/settings/support_email', body: {'value': 'nope'}), status(422));
    await expectLater(api.portal('PUT', '/admin/v1/settings/unknown_key', body: {'value': 'x'}), status(404));
    final fee = await api.portal('PUT', '/admin/v1/settings/service_fee_percent', body: {'value': '5'});
    expect(fee['value'], '5');
    final after = await api.portal('GET', '/admin/v1/settings');
    expect((after['items'] as List).cast<Map>().firstWhere((e) => e['key'] == 'service_fee_percent')['value'], '5');
  });
}
