import 'package:flutter/material.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/theme/app_theme.dart';

const _exampleSettings = AlertSettings(
  readingsInARow: 3,
  repeatEvery: Duration(seconds: 60),
  minConfidence: ConfidenceStop.fourOfFive,
);

String settingsSummary(AlertSettings s) {
  final skip = s.minConfidence == ConfidenceStop.off
      ? 'no confidence skip'
      : 'skip below ${s.minConfidence.label}';
  return '${s.readingsInARow} in a row · '
      'repeat every ${s.repeatEvery.inSeconds} s · $skip';
}

enum _RowKind { normal, skipped, calmBreak, highAlert, lowAlert, ellipsis }

class _TraceRow {
  const _TraceRow(
    this.time,
    this.label,
    this.conf,
    this.run,
    this.what, {
    this.kind = _RowKind.normal,
    this.split = '',
  });

  final String time;
  final FidgetLabel label;
  final String conf;
  final String run;
  final String what;
  final _RowKind kind;
  final String split;
}

const _rows = [
  _TraceRow('+0.0s', FidgetLabel.notFidgeting, '5/5', '0', ''),
  _TraceRow('+2.5s', FidgetLabel.highFidgeting, '5/5', '1', 'run starts'),
  _TraceRow('+5.0s', FidgetLabel.highFidgeting, '4/5', '2', ''),
  _TraceRow('+7.5s', FidgetLabel.lowFidgeting, '3/5', '2',
      'skipped\nrun unchanged',
      kind: _RowKind.skipped),
  _TraceRow('+10.0s', FidgetLabel.highFidgeting, '5/5', '3', 'HIGH ALERT',
      kind: _RowKind.highAlert, split: '3 of 3'),
  _TraceRow('+12.5s', FidgetLabel.lowFidgeting, '4/5', '4',
      'repeat opens at +70.0s'),
  _TraceRow('+15.0s', FidgetLabel.notFidgeting, '5/5', '0', 'run broken',
      kind: _RowKind.calmBreak),
  _TraceRow('+17.5s', FidgetLabel.lowFidgeting, '5/5', '1', 'run restarts'),
  _TraceRow('+20.0s', FidgetLabel.lowFidgeting, '4/5', '2', ''),
  _TraceRow('+22.5s', FidgetLabel.highFidgeting, '4/5', '3',
      'rule met · wait 47 s'),
  _TraceRow('', FidgetLabel.lowFidgeting, '', '', 'fidgeting continues',
      kind: _RowKind.ellipsis),
  _TraceRow('+70.0s', FidgetLabel.lowFidgeting, '5/5', '22', 'LOW ALERT',
      kind: _RowKind.lowAlert, split: '2 low\n1 high'),
];

class AlertRuleScreen extends StatelessWidget {
  const AlertRuleScreen({
    super.key,
    required this.classId,
    required this.deviceId,
  });

  final String classId;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final current = AlertManager.instance.settingsFor(classId, deviceId);
    final exampleDiffers =
        settingsSummary(current) != settingsSummary(_exampleSettings);

    return Scaffold(
      backgroundColor: appSoftGray,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How an alert is decided',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              settingsSummary(current),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (exampleDiffers) ...[
              Text(
                'Worked example at ${settingsSummary(_exampleSettings)}',
                style: const TextStyle(
                  color: appMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
            ],
            AppCard(
              child: Column(
                children: [
                  const _HeaderRow(),
                  for (final row in _rows) _TraceRowView(row),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const AppCard(
              child: Column(
                children: [
                  _Footnote(
                    'A skipped reading does not affect alerts.',
                    ' It neither continues nor breaks the run, so '
                        'three-in-a-row can span more than 7.5 seconds.',
                  ),
                  Divider(height: 28, color: appBorder),
                  _Footnote(
                    'No signal resets alerts.',
                    ' More than 7.5 seconds with no reading at all — watch '
                        'out of range — resets the run to zero.',
                  ),
                  Divider(height: 28, color: appBorder),
                  _Footnote(
                    'Alert ties default to the highest reading.',
                    ' The tie-goes-to-high rule only bites at an even '
                        'setting, where 2 high and 2 low tags as high.',
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

//column widths, WHAT HAPPENS takes the rest
const double _timeW = 48;
const double _readingW = 62;
const double _confW = 34;
const double _runW = 26;
const double _gap = 8;

const _cellStyle = TextStyle(fontSize: 12, color: appInk);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: appMuted,
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: 1,
    );
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: appBorder)),
      ),
      child: const Row(
        children: [
          SizedBox(width: _timeW, child: Text('TIME', style: style)),
          SizedBox(width: _readingW, child: Text('READING', style: style)),
          SizedBox(width: _confW, child: Text('CONF', style: style)),
          SizedBox(
            width: _runW,
            child: Text('RUN', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: _gap * 1.5),
          Expanded(child: Text('WHAT HAPPENS', style: style)),
        ],
      ),
    );
  }
}

class _TraceRowView extends StatelessWidget {
  const _TraceRowView(this.row);

  final _TraceRow row;

  @override
  Widget build(BuildContext context) {
    final kind = row.kind;
    final background = switch (kind) {
      _RowKind.skipped => appSoftGray,
      _RowKind.calmBreak => appTeal.withValues(alpha: 0.07),
      _RowKind.highAlert => appRed.withValues(alpha: 0.07),
      _RowKind.lowAlert => appGold.withValues(alpha: 0.10),
      _ => Colors.transparent,
    };
    final runColor = switch (kind) {
      _RowKind.highAlert => appRed,
      _RowKind.calmBreak => appTealText,
      _ => appInk,
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: background,
        border: const Border(bottom: BorderSide(color: appBorder)),
      ),
      child: kind == _RowKind.ellipsis
          ? Row(
              children: [
                const SizedBox(
                  width: _timeW,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(Icons.more_vert, color: appMuted, size: 18),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.what,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: _timeW,
                  child: Text(
                    row.time,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SizedBox(
                  width: _readingW,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ReadingChip(
                      row.label,
                      struck: kind == _RowKind.skipped,
                    ),
                  ),
                ),
                SizedBox(
                  width: _confW,
                  child: Text(
                    row.conf,
                    style: _cellStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: kind == _RowKind.skipped ? appRed : appMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: _runW,
                  child: Text(
                    row.run,
                    textAlign: TextAlign.right,
                    style: _cellStyle.copyWith(
                      fontWeight: FontWeight.w900,
                      color: runColor,
                    ),
                  ),
                ),
                const SizedBox(width: _gap * 1.5),
                Expanded(child: _What(row)),
              ],
            ),
    );
  }
}

class _What extends StatelessWidget {
  const _What(this.row);

  final _TraceRow row;

  @override
  Widget build(BuildContext context) {
    final isAlert =
        row.kind == _RowKind.highAlert || row.kind == _RowKind.lowAlert;
    if (!isAlert) {
      return Text(row.what, style: _cellStyle.copyWith(color: appMuted));
    }
    final color = row.kind == _RowKind.highAlert ? appRed : appGoldText;
    return Row(
      children: [
        Icon(Icons.warning_rounded, color: color, size: 15),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            row.what,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          row.split,
          textAlign: TextAlign.right,
          style: const TextStyle(color: appMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _ReadingChip extends StatelessWidget {
  const _ReadingChip(this.label, {this.struck = false});

  final FidgetLabel label;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final color = struck
        ? appMuted
        : switch (label) {
            FidgetLabel.notFidgeting => appTealText,
            FidgetLabel.lowFidgeting => appGoldText,
            FidgetLabel.highFidgeting => appRed,
          };
    final tint = struck
        ? appBorder
        : switch (label) {
            FidgetLabel.notFidgeting => appTeal.withValues(alpha: 0.14),
            FidgetLabel.lowFidgeting => appGold.withValues(alpha: 0.16),
            FidgetLabel.highFidgeting => appRed.withValues(alpha: 0.12),
          };
    final text = switch (label) {
      FidgetLabel.notFidgeting => 'Calm',
      FidgetLabel.lowFidgeting => 'Low',
      FidgetLabel.highFidgeting => 'High',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          decoration: struck ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.lead, this.rest);

  final String lead;
  final String rest;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: appMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: lead,
                    style: const TextStyle(
                      color: appInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: rest),
                ],
              ),
              style: const TextStyle(
                color: appMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
