import 'package:flutter/material.dart';

import 'motion.dart';

/// Skeleton loaders wrapped in a [Shimmer] sweep. Each function returns
/// a widget shaped roughly like the real content of one screen, so the
/// user perceives layout stability across the load → data transition.

/// Skeleton for the members list: alternating rows with an avatar,
/// two lines of text, and a trailing chevron / count-badge placeholder.
class MembersListSkeleton extends StatelessWidget {
  const MembersListSkeleton({super.key, this.rowCount = 8});

  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rowCount,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SkeletonCircle(size: 40),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 160, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(width: 200, height: 10),
                  ],
                ),
              ),
              SizedBox(width: 12),
              SkeletonBox(width: 24, height: 16, radius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 16, height: 16, radius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for the ward summary tab: a section header block and a few
/// list rows with a trailing state-chip placeholder.
class SummarySkeleton extends StatelessWidget {
  const SummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var g = 0; g < 2; g++) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(child: SkeletonBox(width: 140, height: 14)),
                  SkeletonBox(width: 24, height: 12),
                ],
              ),
            ),
            for (var i = 0; i < 3; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 180, height: 14),
                          SizedBox(height: 8),
                          SkeletonBox(width: 120, height: 10),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    SkeletonBox(width: 60, height: 22, radius: 8),
                    SizedBox(width: 8),
                    SkeletonBox(width: 16, height: 16, radius: 4),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ],
      ),
    );
  }
}

/// Skeleton for the dashboard: attention hero, a horizontal strip of
/// five pipeline steps, an "active" headline, and a short activity list.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Attention hero.
          Container(
            height: 104,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 24),
          const SkeletonBox(width: 80, height: 14),
          const SizedBox(height: 4),
          const SkeletonBox(width: 140, height: 10),
          const SizedBox(height: 12),
          // Pipeline strip: five ~96-wide pills.
          SizedBox(
            height: 78,
            child: Row(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  Container(
                    width: 96,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  if (i < 4) const SizedBox(width: 12),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Active headline.
          Container(
            height: 82,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 24),
          const SkeletonBox(width: 120, height: 14),
          const SizedBox(height: 8),
          // Three activity rows in a single card.
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 140, height: 12),
                              SizedBox(height: 6),
                              SkeletonBox(width: 200, height: 10),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        SkeletonBox(width: 48, height: 10),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for the member detail screen: an "info card" block at the
/// top then a shorter list of "callings" rows.
class MemberDetailSkeleton extends StatelessWidget {
  const MemberDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SkeletonBox(width: 80, height: 14),
          ),
          for (var i = 0; i < 3; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 160, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 100, height: 10),
                      ],
                    ),
                  ),
                  SkeletonBox(width: 60, height: 22, radius: 8),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
