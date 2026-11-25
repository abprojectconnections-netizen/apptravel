import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';
import 'admin_more_pages.dart';
import 'portal_kit.dart';

/// Moderator portal — summary of the open moderation queue.
class ModeratorDashboardPage extends StatelessWidget {
  const ModeratorDashboardPage({super.key});
  @override
  Widget build(BuildContext context) => PortalPage(
        path: '/moderator/v1/dashboard',
        builder: (context, d) {
          final worst = jmap(d['mostReported']);
          return [
            KpiGrid([
              Kpi('โพสต์ที่ถูกรายงาน', '${numOf(d['reportedPosts']).toInt()}', Icons.flag_rounded),
              Kpi('รายงานที่ค้าง', '${numOf(d['openReports']).toInt()}', Icons.report_rounded),
            ]),
            const SizedBox(height: 16),
            if (worst.isNotEmpty)
              TepCard(
                key: const Key('most-reported'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('โพสต์ที่ถูกรายงานมากที่สุด', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(str(worst['postText']), maxLines: 3, overflow: TextOverflow.ellipsis),
                  Text('โดย ${str(worst['author'])} · ${numOf(worst['reports']).toInt()} รายงาน', style: const TextStyle(color: TepColors.muted, fontSize: 12)),
                ]),
              )
            else
              const SizedBox(height: 200, child: EmptyState(Icons.verified_rounded, 'ไม่มีโพสต์ที่ถูกรายงาน')),
          ];
        },
      );
}

class ModeratorQueuePage extends StatelessWidget {
  const ModeratorQueuePage({super.key});
  @override
  Widget build(BuildContext context) => const ModerationQueueBody(base: '/moderator/v1');
}
