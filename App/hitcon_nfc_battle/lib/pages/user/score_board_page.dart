import 'package:flutter/material.dart';

import 'pixel_theme.dart';

class ScoreBoardPage extends StatelessWidget {
  const ScoreBoardPage({super.key, this.scheme});

  final PixelScheme? scheme;

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(scheme ?? PixelTheme.defaultScheme);

    final List<Map<String, Object>> ranks = <Map<String, Object>>[
      <String, Object>{'name': 'TEAM BOSS', 'score': 1280, 'badge': 'S', 'color': PixelTheme.accent},
      <String, Object>{'name': 'PIXEL HUNTER', 'score': 1160, 'badge': 'A', 'color': PixelTheme.accentBlue},
      <String, Object>{'name': 'NFC RANGER', 'score': 1040, 'badge': 'B', 'color': PixelTheme.success},
      <String, Object>{'name': 'TAG WIZARD', 'score': 920, 'badge': 'C', 'color': PixelTheme.warning},
      <String, Object>{'name': 'REEDER', 'score': 780, 'badge': 'D', 'color': PixelTheme.textGray},
    ];

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
        primaryTextTheme: Theme.of(context).primaryTextTheme.apply(fontFamily: 'Unifont'),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Unifont'),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _BoardHeader(),
            const SizedBox(height: 12),
            _StatRow(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                border: Border.all(color: PixelTheme.border, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '排行榜',
                    style: TextStyle(
                      color: PixelTheme.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ranks.length,
                    separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, Object> row = ranks[index];
                      final Color color = row['color'] as Color;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: PixelTheme.bgDark,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color,
                                border: Border.all(color: PixelTheme.bgDark, width: 2),
                              ),
                              child: Text(
                                '${row['badge']}',
                                style: TextStyle(
                                  color: PixelTheme.bgDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row['name']}',
                                    style: TextStyle(
                                      color: PixelTheme.textWhite,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'COMBO SCORE',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${row['score']}',
                              style: TextStyle(
                                color: color,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SCORE BOARD',
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '活動中累積分數與排名會顯示在這裡。',
            style: TextStyle(color: PixelTheme.textWhite),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _StatCard(label: '今日活躍', value: '18')),
        SizedBox(width: 8),
        Expanded(child: _StatCard(label: '已完成', value: '42')),
        SizedBox(width: 8),
        Expanded(child: _StatCard(label: '最高分', value: '1280')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: PixelTheme.textGray,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
