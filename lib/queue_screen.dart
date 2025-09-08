import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import 'forwarding_queue.dart';
import 'retry_defs.dart';
// ResponsiveScaffoldBody is not used here to avoid nested scrollables.

class QueueScreen extends StatefulWidget {
  const QueueScreen({Key? key}) : super(key: key);

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final _queue = ForwardingRequestQueue();
  final _scrollController = ScrollController();

  QueueItemStatus? _filter;
  QueueCounts? _counts;
  List<ForwardingQueueItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 50;
  final Set<int?> _expanded = {};

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final c = await _queue.getCounts();
    if (!mounted) return;
    setState(() => _counts = c);
  }

  Future<void> _refresh() async {
    setState(() {
      _items = [];
      _offset = 0;
      _hasMore = true;
    });
    await _loadCounts();
    await _loadMore();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final page = await _queue.listItems(
        status: _filter,
        limit: _limit,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _limit;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _statusLabel(QueueItemStatus s) {
    switch (s) {
      case QueueItemStatus.pending:
        return 'Pending';
      case QueueItemStatus.success:
        return 'Success';
      case QueueItemStatus.partialFailure:
        return 'Partial';
      case QueueItemStatus.failure:
        return 'Failed';
    }
  }

  Color _statusColor(QueueItemStatus s) {
    switch (s) {
      case QueueItemStatus.pending:
        return Colors.orange.shade600;
      case QueueItemStatus.success:
        return Colors.green.shade600;
      case QueueItemStatus.partialFailure:
        return Colors.amber.shade700;
      case QueueItemStatus.failure:
        return Colors.red.shade400;
    }
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  String _two(int v) => v < 10 ? '0$v' : '$v';

  Widget _buildFilterChips() {
    final counts = _counts;
    String labelAll = 'All';
    if (counts != null) labelAll = 'All (${counts.total})';
    final pendingLabel =
        counts == null ? 'Pending' : 'Pending (${counts.pending})';
    final successLabel =
        counts == null ? 'Success' : 'Success (${counts.success})';
    final partialLabel =
        counts == null ? 'Partial' : 'Partial (${counts.partialFailure})';
    final failureLabel =
        counts == null ? 'Failed' : 'Failed (${counts.failure})';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ChoiceChip(
          label: Text(labelAll),
          selected: _filter == null,
          onSelected: (b) {
            if (_filter != null) {
              setState(() => _filter = null);
              _refresh();
            }
          },
        ),
        SizedBox(width: 6),
        ChoiceChip(
          label: Text(pendingLabel),
          selected: _filter == QueueItemStatus.pending,
          onSelected: (b) {
            setState(() => _filter = QueueItemStatus.pending);
            _refresh();
          },
        ),
        SizedBox(width: 6),
        ChoiceChip(
          label: Text(successLabel),
          selected: _filter == QueueItemStatus.success,
          onSelected: (b) {
            setState(() => _filter = QueueItemStatus.success);
            _refresh();
          },
        ),
        SizedBox(width: 6),
        ChoiceChip(
          label: Text(partialLabel),
          selected: _filter == QueueItemStatus.partialFailure,
          onSelected: (b) {
            setState(() => _filter = QueueItemStatus.partialFailure);
            _refresh();
          },
        ),
        SizedBox(width: 6),
        ChoiceChip(
          label: Text(failureLabel),
          selected: _filter == QueueItemStatus.failure,
          onSelected: (b) {
            setState(() => _filter = QueueItemStatus.failure);
            _refresh();
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Forwarding Queue'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
          )
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFilterChips(),
                      SizedBox(height: 8),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: _items.length +
                                (_isLoading || _hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _items.length) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                );
                              }
                              final item = _items[index];
                              final address =
                                  item.sms['address']?.toString() ?? 'Unknown';
                              final body = item.sms['body']?.toString() ?? '';
                              final isExpanded = _expanded.contains(item.id);
                              return Card(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expanded.remove(item.id);
                                      } else {
                                        _expanded.add(item.id);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    address,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    body,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        color: Colors.black87),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Chip(
                                              label: Text(
                                                  _statusLabel(item.status)),
                                              backgroundColor:
                                                  _statusColor(item.status),
                                              labelStyle: TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatDate(item.createdAtMs),
                                              style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontSize: 12),
                                            ),
                                            Icon(isExpanded
                                                ? Icons.expand_less
                                                : Icons.expand_more),
                                          ],
                                        ),
                                        if (isExpanded) ...[
                                          SizedBox(height: 8),
                                          _buildForwardersProgress(item),
                                          SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              icon: Icon(Icons.code),
                                              label: Text('View JSON'),
                                              onPressed: () => _showJson(item),
                                            ),
                                          )
                                        ]
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForwardersProgress(ForwardingQueueItem item) {
    final entries = item.forwarders.entries.toList();
    if (entries.isEmpty) return Text('No per-forwarder data');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final prog = e.value;
        final state = prog.state;
        final color = switch (state) {
          ForwarderAttemptState.success => Colors.green.shade600,
          ForwarderAttemptState.retriableFailure => Colors.orange.shade600,
          ForwarderAttemptState.nonRetriableFailure => Colors.red.shade400,
          ForwarderAttemptState.pending => Colors.blueGrey.shade400,
        };
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 8,
                height: 8,
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'State: ${forwarderAttemptStateToString(state)} | Retries: ${prog.retryCount}/${prog.maxRetries}',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    if (prog.lastError != null && prog.lastError!.isNotEmpty)
                      Text(
                        'Last error: ${prog.lastError}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _showJson(ForwardingQueueItem item) {
    final smsJson = item.sms;
    final fwdJson = item.forwarders.map((k, v) => MapEntry(k, v.toJson()));
    final encoder = const JsonEncoder.withIndent('  ');
    final smsPretty = encoder.convert(smsJson);
    final fwdPretty = encoder.convert(fwdJson);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SMS JSON',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: smsPretty));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied SMS JSON to clipboard')),
                      );
                    },
                    child: SelectableText(
                      smsPretty,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('Forwarders JSON',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: fwdPretty));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('Copied forwarders JSON to clipboard')),
                      );
                    },
                    child: SelectableText(
                      fwdPretty,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
