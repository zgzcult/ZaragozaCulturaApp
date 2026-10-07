/// Buzón de avisos: los avisos de favoritos que ya han llegado, con los que
/// siguen sin leer destacados. Al tocar uno se abre su actividad.
library;

import 'package:flutter/material.dart';

import 'brand.dart';
import 'main.dart';
import 'reminders.dart';

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// «Hoy», «Ayer» o «5 oct», según cuándo llegó el aviso.
String reminderDayLabel(DateTime when, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(when.year, when.month, when.day)).inDays;
  if (days == 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  return '${when.day} ${_months[when.month - 1]}';
}

class NotificationsScreen extends StatefulWidget {
  final ZaragozaEventsRepository repository;
  final DateTime Function() clock;

  const NotificationsScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.clock = DateTime.now,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<ReminderEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ReminderInbox.delivered(now: widget.clock());
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _open(ReminderEntry entry) async {
    await ReminderInbox.markRead(eventId: entry.eventId, now: widget.clock());
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventLinkScreen(
          eventId: entry.eventId,
          repository: widget.repository,
        ),
      ),
    );
    _load();
  }

  Future<void> _markAllRead() async {
    await ReminderInbox.markRead(now: widget.clock());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final hasUnread = entries?.any((e) => !e.read) ?? false;
    final Widget body;
    if (entries == null) {
      body = const SizedBox.shrink();
    } else if (entries.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_none,
                size: 48,
                color: Color(0xFF9AA8B8),
              ),
              const SizedBox(height: 12),
              const Text(
                'No tienes avisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.slate, height: 1.4),
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        itemCount: entries.length,
        itemBuilder: (context, index) => _ReminderTile(
          entry: entries[index],
          dayLabel: reminderDayLabel(entries[index].when, widget.clock()),
          onTap: () => _open(entries[index]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(
        title: const Text('Avisos'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Marcar leídos'),
            ),
        ],
      ),
      body: body,
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final ReminderEntry entry;
  final String dayLabel;
  final VoidCallback onTap;

  const _ReminderTile({
    required this.entry,
    required this.dayLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !entry.read;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: unread ? 'Sin leer. ${entry.title}' : entry.title,
        child: Material(
          color: unread ? Colors.white : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: unread ? Brand.skyLine : Brand.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Punto coral: aviso sin leer.
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: unread ? Brand.coral : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: Brand.navy,
                          ),
                        ),
                        if (entry.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            entry.body,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Brand.slate,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dayLabel,
                    style: const TextStyle(fontSize: 12, color: Brand.slate),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
