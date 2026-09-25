import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'sheets.dart';
import 'widgets/common.dart';

class EntityScreen extends StatelessWidget {
  const EntityScreen({super.key, required this.entityId});
  final String entityId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final e = store.byId(entityId);
    if (e == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This entry no longer exists.')));
    }
    final cap = store.spoilerChapter;
    final facts = e.visibleFacts(cap);
    final hidden = e.facts.length - facts.length;
    final links = store.linksFor(e.id);
    final mentions = store.mentionsIn(e);
    final backlinks = store.mentionedBy(e).where((b) => !mentions.any((m) => m.id == b.id)).toList();
    final color = Syl.cardColor(e.id);
    final busy = store.isBusy(e.id);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ---- coloured header -------------------------------------------------
          Container(
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36))),
            padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 12, 18, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                RoundIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  background: Syl.white.withValues(alpha: 0.6),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                RoundIconButton(
                  icon: Icons.link,
                  tooltip: 'Link to another entry',
                  background: Syl.white.withValues(alpha: 0.6),
                  onPressed: () => showLinkSheet(context, e),
                ),
                const SizedBox(width: 8),
                RoundIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',
                  background: Syl.white.withValues(alpha: 0.6),
                  onPressed: () => showEditEntity(context, e),
                ),
              ]),
              const SizedBox(height: 20),
              Wrap(spacing: 6, runSpacing: 6, children: [
                SoftTag(e.type, dot: Syl.typeDot(e.type), background: Syl.ink.withValues(alpha: 0.1)),
                if (e.book != null) SoftTag(e.book!, background: Syl.ink.withValues(alpha: 0.1)),
                if (e.external.wikidataId != null) SoftTag(e.external.wikidataId!, background: Syl.ink.withValues(alpha: 0.1)),
              ]),
              const SizedBox(height: 10),
              Text(e.name, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 52)),
              if (e.external.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_capitalise(e.external.description), style: const TextStyle(fontSize: 15)),
              ],
              if (e.external.aliases.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Also: ${e.external.aliases.join(', ')}', style: const TextStyle(fontSize: 13, color: Syl.muted)),
              ],
              const SizedBox(height: 18),
              Row(children: [
                _Stat(value: '${facts.length}', label: facts.length == 1 ? 'fact' : 'facts'),
                const SizedBox(width: 8),
                _Stat(value: '${links.length + mentions.length}', label: 'connections'),
                const SizedBox(width: 8),
                _Stat(value: 'Ch.${e.discoveryChapter}', label: 'first seen'),
              ]),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _LoreCard(entity: e, busy: busy, factCount: facts.length),
              if (e.external.wikidataId == null) ...[
                const SizedBox(height: 10),
                _WikidataPrompt(entity: e, busy: busy),
              ],
              const SizedBox(height: 22),
              SectionTitle('Facts',
                  trailing: PillButton(label: 'Add fact', icon: Icons.add, onTap: () => showQuickAdd(context, entity: e))),
              const SizedBox(height: 10),
              if (facts.isEmpty)
                const _Hint('No facts yet. Add what you learn as you read, with the chapter.'),
              for (final f in facts) _FactRow(entity: e, fact: f),
              if (hidden > 0)
                _Hint('$hidden more ${hidden == 1 ? 'fact is' : 'facts are'} hidden by the spoiler shield (past chapter $cap).'),
              const SizedBox(height: 22),
              SectionTitle('Connections',
                  trailing: PillButton(label: 'Link', icon: Icons.add, onTap: () => showLinkSheet(context, e))),
              const SizedBox(height: 10),
              if (links.isEmpty && mentions.isEmpty && backlinks.isEmpty)
                const _Hint('No connections yet. Link this entry, or mention other names in your facts.'),
              for (final r in links) _LinkRow(entity: e, rel: r),
              for (final m in mentions) _MentionRow(other: m, label: 'Named in these facts'),
              for (final b in backlinks) _MentionRow(other: b, label: 'Mentions ${e.name}'),
            ]),
          ),
        ],
      ),
    );
  }

  static String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Syl.white.withValues(alpha: 0.55), borderRadius: const BorderRadius.all(Radius.circular(18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

class _LoreCard extends StatelessWidget {
  const _LoreCard({required this.entity, required this.busy, required this.factCount});
  final Entity entity;
  final bool busy;
  final int factCount;

  Future<void> _generate(BuildContext context) async {
    try {
      await context.read<LibraryStore>().generateLore(entity);
    } catch (e) {
      if (context.mounted) showMessage(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final lore = entity.lore;
    final button = SizedBox(
      height: 40,
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Syl.paper, foregroundColor: Syl.ink, minimumSize: const Size(64, 40)),
        onPressed: busy || factCount == 0 ? null : () => _generate(context),
        child: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(lore.isEmpty ? 'Write' : 'Rewrite'),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Syl.ink, borderRadius: Syl.r24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: Syl.lilac, borderRadius: Syl.r14),
            child: const Icon(Icons.auto_awesome, color: Syl.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lore.isEmpty ? 'No biography yet' : 'Lore',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Syl.paper)),
              Text(
                busy
                    ? 'Your PC is writing...'
                    : lore.isEmpty
                        ? (factCount == 0 ? 'Add a fact, then your PC can write one' : 'Your PC can write one from your facts')
                        : 'From facts up to ch. ${lore.spoilerLimitChapter ?? '?'} · ${lore.model ?? 'local model'}',
                style: const TextStyle(fontSize: 12, color: Syl.onInkMuted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          button,
        ]),
        if (!lore.isEmpty) ...[
          const SizedBox(height: 14),
          if (lore.description.isNotEmpty)
            Text(lore.description, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Syl.paper, height: 1.35)),
          if (lore.biography.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(lore.biography, style: const TextStyle(fontSize: 14, color: Syl.paper, height: 1.45)),
          ],
          if (lore.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in lore.tags) SoftTag(t, background: Syl.butter),
            ]),
          ],
        ],
      ]),
    );
  }
}

class _WikidataPrompt extends StatelessWidget {
  const _WikidataPrompt({required this.entity, required this.busy});
  final Entity entity;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Syl.white,
      borderRadius: Syl.r20,
      child: InkWell(
        borderRadius: Syl.r20,
        onTap: busy
            ? null
            : () async {
                final store = context.read<LibraryStore>();
                final info = await pickFromWikidata(context, entity.name, hint: entity.book);
                if (info == null || !context.mounted) return;
                try {
                  await store.linkWikidata(entity, info.id);
                  if (context.mounted) showMessage(context, 'Linked to ${info.label} (${info.id})');
                } catch (e) {
                  if (context.mounted) showMessage(context, e.toString());
                }
              },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(Icons.travel_explore, size: 22),
            SizedBox(width: 12),
            Expanded(child: Text('Look up on Wikidata for a description, type and other names', style: TextStyle(fontSize: 14))),
            Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.entity, required this.fact});
  final Entity entity;
  final Fact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(fact.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: Syl.danger.withValues(alpha: 0.15), borderRadius: Syl.r20),
          child: const Icon(Icons.delete_outline, color: Syl.danger),
        ),
        confirmDismiss: (_) async =>
            await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Delete this fact?'),
                content: Text(fact.text),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
                  TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete', style: TextStyle(color: Syl.danger))),
                ],
              ),
            ) ??
            false,
        onDismissed: (_) => context.read<LibraryStore>().removeFact(entity, fact.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Syl.white, borderRadius: Syl.r20),
          child: Row(children: [
            ChapterBadge(fact.chapter, color: Syl.pastels[fact.chapter % Syl.pastels.length]),
            const SizedBox(width: 12),
            Expanded(child: Text(fact.text, style: const TextStyle(fontSize: 15, height: 1.35))),
          ]),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.entity, required this.rel});
  final Entity entity;
  final Relationship rel;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final other = store.byId(rel.other(entity.id));
    if (other == null) return const SizedBox.shrink();
    final outgoing = rel.source == entity.id;
    final label = outgoing ? '${rel.type} of' : '${rel.type}:';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Syl.cardColor(other.id),
        borderRadius: Syl.r20,
        child: InkWell(
          borderRadius: Syl.r20,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: other.id))),
          onLongPress: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Remove this link?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
                  TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove', style: TextStyle(color: Syl.danger))),
                ],
              ),
            );
            if (ok == true) await store.removeLink(rel);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              InitialAvatar(other.initial),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12)),
                  Text(other.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (rel.description.isNotEmpty) Text(rel.description, style: const TextStyle(fontSize: 13)),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({required this.other, required this.label});
  final Entity other;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: Syl.r20,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: other.id))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: Syl.r20, border: Border.all(color: Syl.line, width: 1.5)),
          child: Row(children: [
            InitialAvatar(other.initial, background: Syl.cardColor(other.id)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Syl.muted)),
                Text(other.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: const TextStyle(color: Syl.muted, fontSize: 14)),
      );
}
