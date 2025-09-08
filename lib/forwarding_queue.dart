import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sms_forwarder/utils.dart';
import 'package:sqflite/sqflite.dart';
import 'retry_defs.dart';

/// Overall processing status for a queued forwarding request.
enum QueueItemStatus { pending, success, partialFailure, failure }

QueueItemStatus queueItemStatusFromString(String s) {
  switch (s) {
    case 'pending':
      return QueueItemStatus.pending;
    case 'success':
      return QueueItemStatus.success;
    case 'partial_failure':
      return QueueItemStatus.partialFailure;
    case 'failure':
      return QueueItemStatus.failure;
    default:
      return QueueItemStatus.pending;
  }
}

String queueItemStatusToString(QueueItemStatus s) {
  switch (s) {
    case QueueItemStatus.pending:
      return 'pending';
    case QueueItemStatus.success:
      return 'success';
    case QueueItemStatus.partialFailure:
      return 'partial_failure';
    case QueueItemStatus.failure:
      return 'failure';
  }
}

/// Per-forwarder processing state stored in the queue item JSON.
class ForwarderProgress {
  final String forwarderName;
  ForwarderAttemptState state;
  int retryCount;
  String? lastError;
  int maxRetries;

  ForwarderProgress({
    required this.forwarderName,
    required this.state,
    required this.retryCount,
    required this.maxRetries,
    this.lastError,
  });

  Map<String, dynamic> toJson() {
    return {
      'forwarderName': forwarderName,
      'state': forwarderAttemptStateToString(state),
      'retryCount': retryCount,
      'maxRetries': maxRetries,
      if (lastError != null) 'lastError': lastError,
    };
  }

  static ForwarderProgress fromJson(Map<String, dynamic> json) {
    return ForwarderProgress(
      forwarderName: json['forwarderName'] as String,
      state: forwarderAttemptStateFromString(json['state'] as String),
      retryCount: (json['retryCount'] ?? 0) as int,
      maxRetries: (json['maxRetries'] ?? 5) as int,
      lastError: json['lastError'] as String?,
    );
  }
}

/// A single queue item persisted in SQLite.
class ForwardingQueueItem {
  int? id;
  final String smsKey;
  final Map<String, dynamic> sms;
  Map<String, ForwarderProgress> forwarders; // name -> progress
  QueueItemStatus status;
  int createdAtMs;
  int updatedAtMs;
  int retryCount;
  int? reservedAtMs;
  int? lastAttemptAtMs;

  ForwardingQueueItem(
      {this.id,
      required this.smsKey,
      required this.sms,
      required this.forwarders,
      required this.status,
      required this.createdAtMs,
      required this.updatedAtMs,
      required this.retryCount,
      this.reservedAtMs,
      this.lastAttemptAtMs});

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'sms_key': smsKey,
      'sms_json': toJsonString(sms),
      'forwarders_json': toJsonString(
        forwarders.map((k, v) => MapEntry(k, v.toJson())),
      ),
      'status': queueItemStatusToString(status),
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'retry_count': retryCount,
      'reserved_at_ms': reservedAtMs,
      'last_attempt_at_ms': lastAttemptAtMs,
    };
  }

  static ForwardingQueueItem fromDbMap(Map<String, dynamic> m) {
    final forwardersMap =
        (json.decode(m['forwarders_json'] as String) as Map<String, dynamic>)
            .map((key, value) => MapEntry(
                key,
                ForwarderProgress.fromJson(
                    (value as Map).map((k, v) => MapEntry(k.toString(), v)))));

    return ForwardingQueueItem(
      id: m['id'] as int?,
      smsKey: m['sms_key'] as String,
      sms: (json.decode(m['sms_json'] as String) as Map)
          .map((k, v) => MapEntry(k.toString(), v)),
      forwarders: forwardersMap,
      status: queueItemStatusFromString(m['status'] as String),
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int,
      retryCount: (m['retry_count'] ?? 0) as int,
      reservedAtMs: m['reserved_at_ms'] as int?,
      lastAttemptAtMs: m['last_attempt_at_ms'] as int?,
    );
  }
}

/// SQLite-backed queue for retrying failed forwarding requests.
class ForwardingRequestQueue {
  static final ForwardingRequestQueue _instance = ForwardingRequestQueue._();

  ForwardingRequestQueue._();

  factory ForwardingRequestQueue() => _instance;

  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final dbPath = p.join(dir, 'forwarding_queue.db');
    _db = await openDatabase(dbPath, version: 2, onCreate: (db, version) async {
      print('[ForwardingRequestQueue] Initializing the database');
      await db.execute('''
          CREATE TABLE forwarding_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sms_key TEXT NOT NULL,
            sms_json TEXT NOT NULL,
            forwarders_json TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            reserved_at_ms INTEGER,
            last_attempt_at_ms INTEGER
          );
        ''');
      await db.execute(
          'CREATE UNIQUE INDEX uq_forwarding_queue_sms_key ON forwarding_queue(sms_key)');
      await db.execute(
          "CREATE INDEX idx_forwarding_queue_status ON forwarding_queue(status)");
    });
    return _db!;
  }

  /// Inserts or updates a queue item by `smsKey`.
  Future<void> putOrUpdate(ForwardingQueueItem item) async {
    print('[ForwardingRequestQueue] Placing new item: `${item.smsKey}`');
    final db = await _getDb();
    item.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query('forwarding_queue',
        where: 'sms_key = ?', whereArgs: [item.smsKey], limit: 1);
    if (existing.isEmpty) {
      await db.insert('forwarding_queue', item.toDbMap());
    } else {
      final existingItem = ForwardingQueueItem.fromDbMap(existing.first);
      // Merge forwarder progress: keep successes, update failures/pending
      final mergedForwarders =
          Map<String, ForwarderProgress>.from(existingItem.forwarders);
      item.forwarders.forEach((name, newProg) {
        final old = mergedForwarders[name];
        if (old == null) {
          mergedForwarders[name] = newProg;
          return;
        }
        if (old.state == ForwarderAttemptState.success) {
          mergedForwarders[name] = old;
        } else {
          // Prefer new state; keep max retry count and aggregate retry counts
          mergedForwarders[name] = ForwarderProgress(
            forwarderName: name,
            state: newProg.state,
            retryCount: (old.retryCount > newProg.retryCount)
                ? old.retryCount
                : newProg.retryCount,
            maxRetries: newProg.maxRetries,
            lastError: newProg.lastError ?? old.lastError,
          );
        }
      });

      final merged = ForwardingQueueItem(
        id: existingItem.id,
        smsKey: existingItem.smsKey,
        sms: item.sms,
        forwarders: mergedForwarders,
        status: item.status,
        createdAtMs: existingItem.createdAtMs,
        updatedAtMs: item.updatedAtMs,
        retryCount: (existingItem.retryCount > item.retryCount)
            ? existingItem.retryCount
            : item.retryCount,
        reservedAtMs: null,
        lastAttemptAtMs: existingItem.lastAttemptAtMs,
      );

      await db.update('forwarding_queue', merged.toDbMap(),
          where: 'id = ?', whereArgs: [existingItem.id]);
    }
  }

  /// Pops one pending item and reserves it to avoid concurrent processing.
  Future<ForwardingQueueItem?> popPendingAndReserve() async {
    final db = await _getDb();
    return await db.transaction<ForwardingQueueItem?>((txn) async {
      final rows = await txn.query('forwarding_queue',
          where:
              'status = ? AND (reserved_at_ms IS NULL OR reserved_at_ms < ?)',
          whereArgs: [
            'pending',
            DateTime.now().millisecondsSinceEpoch -
                kReservationTtl.inMilliseconds
          ],
          orderBy: 'created_at_ms ASC',
          limit: 1);
      if (rows.isEmpty) return null;
      final item = ForwardingQueueItem.fromDbMap(rows.first);
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
          'forwarding_queue', {'reserved_at_ms': now, 'updated_at_ms': now},
          where: 'id = ?', whereArgs: [item.id]);
      print('[ForwardingRequestQueue] Item reserved: `${item.smsKey}`');
      item..reservedAtMs = now;
      return item;
    });
  }

  Future<void> updateItem(ForwardingQueueItem item) async {
    final db = await _getDb();
    item.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await db.update('forwarding_queue', item.toDbMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }
}
