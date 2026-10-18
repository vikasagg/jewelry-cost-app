/// Daily physical stock counting — kept entirely separate from jewellery
/// pricing: nothing here reads or writes gold rates, prices or cost
/// calculation records.
library;

/// One countable stock line (e.g. LGR under Ring).
class StockItem {
  const StockItem(this.code, this.name, this.group);

  /// Short code used in reports, e.g. "LGR".
  final String code;
  final String name;

  /// Category the item is totalled under, e.g. "Ring".
  final String group;

  /// "Ring – LGR" for grouped items, else the name.
  String get label => group == name ? name : '$group – $code';
}

/// Categories counted every day, in display order.
const stockItems = [
  StockItem('LGR', 'Ladies Gold Ring', 'Ring'),
  StockItem('GGR', "Gent's Gold Ring", 'Ring'),
  StockItem('GE', 'Gold Earring', 'Earring'),
  StockItem('DE', 'Diamond Earring', 'Earring'),
  StockItem('PENDANT', 'Pendant', 'Pendant'),
  StockItem('PSET', 'Pendant Set', 'Pendant Set'),
  StockItem('NSET', 'Necklace Set', 'Necklace Set'),
  StockItem('BANGLE', 'Bangle', 'Bangle'),
  StockItem('TIKKA', 'Tikka', 'Tikka'),
  StockItem('DSET', 'Diamond Set', 'Diamond Set'),
  StockItem('CHAIN', 'Chain', 'Chain'),
  StockItem('CHASHMA', 'Chashma', 'Chashma'),
  StockItem('WATCH', 'Watch', 'Watch'),
  StockItem('NATH', 'Nath', 'Nath'),
];

/// Category names in display order (Ring, Earring, Pendant…).
List<String> get stockGroups => [
  for (final i in stockItems)
    if (stockItems.firstWhere((x) => x.group == i.group) == i) i.group,
];

enum StockStatus {
  /// Being counted; employees may edit.
  draft('Draft'),

  /// Count finished, waiting for a manager to verify.
  submitted('Awaiting approval'),

  /// Approved by a manager: becomes the next day's opening stock.
  verified('Verified');

  const StockStatus(this.label);
  final String label;
}

/// A manager-approved change to the expected stock of one item
/// (e.g. +2 received from the workshop, −1 sold). Never edits an earlier
/// day's closing balance.
class StockAdjustment {
  const StockAdjustment({
    required this.code,
    required this.qty,
    required this.reason,
    required this.approvedBy,
    required this.at,
  });

  final String code;
  final int qty;
  final String reason;
  final String approvedBy;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'code': code,
    'qty': qty,
    'reason': reason,
    'approvedBy': approvedBy,
    'at': at.toIso8601String(),
  };

  factory StockAdjustment.fromJson(Map<String, dynamic> j) => StockAdjustment(
    code: j['code'] as String,
    qty: (j['qty'] as num).toInt(),
    reason: j['reason'] as String? ?? '',
    approvedBy: j['approvedBy'] as String? ?? '',
    at: DateTime.parse(j['at'] as String),
  );
}

/// One entry in a day's audit trail.
class StockAuditEvent {
  const StockAuditEvent({
    required this.at,
    required this.actor,
    required this.action,
    this.detail,
  });

  final DateTime at;
  final String actor;
  final String action;
  final String? detail;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'actor': actor,
    'action': action,
    if (detail != null) 'detail': detail,
  };

  factory StockAuditEvent.fromJson(Map<String, dynamic> j) => StockAuditEvent(
    at: DateTime.parse(j['at'] as String),
    actor: j['actor'] as String? ?? '',
    action: j['action'] as String,
    detail: j['detail'] as String?,
  );
}

/// The physical stock count for one day.
class DailyStock {
  const DailyStock({
    required this.date,
    this.employee = '',
    this.counts = const {},
    this.opening = const {},
    this.openingFrom,
    this.remarks = const {},
    this.note = '',
    this.adjustments = const [],
    this.status = StockStatus.draft,
    this.approvedBy,
    this.approvedAt,
    this.audit = const [],
  });

  /// Stock date as yyyy-MM-dd.
  final String date;
  final String employee;

  /// Physical count per item code; missing = not counted yet.
  final Map<String, int> counts;

  /// Expected opening per item: the previous verified closing, frozen when
  /// this day is verified.
  final Map<String, int> opening;

  /// Date (yyyy-MM-dd) of the verified day [opening] came from; null when
  /// there was none (the first count sets the baseline).
  final String? openingFrom;

  /// Employee remarks per item code (e.g. "1 sent for repair").
  final Map<String, String> remarks;

  /// Overall remark for the day.
  final String note;
  final List<StockAdjustment> adjustments;
  final StockStatus status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final List<StockAuditEvent> audit;

  bool get hasOpening => openingFrom != null;
  bool get isLocked => status != StockStatus.draft;

  int previousClosing(String code) => opening[code] ?? 0;

  int adjustmentFor(String code) =>
      adjustments.where((a) => a.code == code).fold(0, (sum, a) => sum + a.qty);

  /// Today's expected stock: previous verified closing + approved
  /// adjustments.
  int expected(String code) => previousClosing(code) + adjustmentFor(code);

  int? count(String code) => counts[code];

  /// Physical − expected (negative = shortage, positive = excess). Null
  /// until counted, and on the first count (nothing to compare with yet).
  int? difference(String code) {
    final c = counts[code];
    return c == null || !hasOpening ? null : c - expected(code);
  }

  bool get allCounted => stockItems.every((i) => counts.containsKey(i.code));

  Iterable<StockItem> get discrepancies =>
      stockItems.where((i) => (difference(i.code) ?? 0) != 0);

  /// Discrepant items still without a remark.
  Iterable<StockItem> get unexplained =>
      discrepancies.where((i) => (remarks[i.code] ?? '').trim().isEmpty);

  int groupExpected(String group) => stockItems
      .where((i) => i.group == group)
      .fold(0, (s, i) => s + expected(i.code));

  int groupCount(String group) => stockItems
      .where((i) => i.group == group)
      .fold(0, (s, i) => s + (counts[i.code] ?? 0));

  int get totalExpected => stockItems.fold(0, (s, i) => s + expected(i.code));
  int get totalCount => stockItems.fold(0, (s, i) => s + (counts[i.code] ?? 0));
  int get totalDifference => hasOpening ? totalCount - totalExpected : 0;

  DailyStock copyWith({
    String? employee,
    Map<String, int>? counts,
    Map<String, int>? opening,
    String? openingFrom,
    bool clearOpeningFrom = false,
    Map<String, String>? remarks,
    String? note,
    List<StockAdjustment>? adjustments,
    StockStatus? status,
    String? approvedBy,
    DateTime? approvedAt,
    bool clearApproval = false,
    List<StockAuditEvent>? audit,
  }) => DailyStock(
    date: date,
    employee: employee ?? this.employee,
    counts: counts ?? this.counts,
    opening: opening ?? this.opening,
    openingFrom: clearOpeningFrom ? null : openingFrom ?? this.openingFrom,
    remarks: remarks ?? this.remarks,
    note: note ?? this.note,
    adjustments: adjustments ?? this.adjustments,
    status: status ?? this.status,
    approvedBy: clearApproval ? null : approvedBy ?? this.approvedBy,
    approvedAt: clearApproval ? null : approvedAt ?? this.approvedAt,
    audit: audit ?? this.audit,
  );

  /// A copy with [event] appended to the audit trail.
  DailyStock logged(StockAuditEvent event) =>
      copyWith(audit: [...audit, event]);

  Map<String, dynamic> toJson() => {
    'date': date,
    'employee': employee,
    'counts': counts,
    'opening': opening,
    if (openingFrom != null) 'openingFrom': openingFrom,
    'remarks': remarks,
    'note': note,
    'adjustments': [for (final a in adjustments) a.toJson()],
    'status': status.name,
    if (approvedBy != null) 'approvedBy': approvedBy,
    if (approvedAt != null) 'approvedAt': approvedAt!.toIso8601String(),
    'audit': [for (final e in audit) e.toJson()],
  };

  factory DailyStock.fromJson(Map<String, dynamic> j) {
    Map<String, int> ints(Object? m) => {
      for (final e in ((m as Map?) ?? {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    return DailyStock(
      date: j['date'] as String,
      employee: j['employee'] as String? ?? '',
      counts: ints(j['counts']),
      opening: ints(j['opening']),
      openingFrom: j['openingFrom'] as String?,
      remarks: {
        for (final e in ((j['remarks'] as Map?) ?? {}).entries)
          e.key as String: e.value as String,
      },
      note: j['note'] as String? ?? '',
      adjustments: [
        for (final a in (j['adjustments'] as List? ?? []))
          StockAdjustment.fromJson((a as Map).cast<String, dynamic>()),
      ],
      status: StockStatus.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => StockStatus.draft,
      ),
      approvedBy: j['approvedBy'] as String?,
      approvedAt: j['approvedAt'] == null
          ? null
          : DateTime.parse(j['approvedAt'] as String),
      audit: [
        for (final e in (j['audit'] as List? ?? []))
          StockAuditEvent.fromJson((e as Map).cast<String, dynamic>()),
      ],
    );
  }
}
