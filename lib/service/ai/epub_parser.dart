import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/utils/log/common.dart';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

class EpubChapter {
  const EpubChapter({
    required this.href,
    required this.label,
    required this.content,
  });

  final String href;
  final String label;
  final String content;
}

class EpubBookInfo {
  const EpubBookInfo({
    required this.title,
    required this.author,
    required this.chapters,
  });

  final String title;
  final String author;
  final List<EpubChapter> chapters;
}

Future<EpubBookInfo> parseEpubFile(String filePath) async {
  final file = File(filePath);
  final bytes = await file.readAsBytes();
  return parseEpubBytes(bytes);
}

Future<EpubBookInfo> parseEpubBytes(Uint8List bytes) async {
  final archive = ZipDecoder().decodeBytes(bytes);

  // Find container.xml to get rootfile path
  final containerFile = archive.findFile('META-INF/container.xml');
  if (containerFile == null) {
    throw Exception('Invalid EPUB: missing container.xml');
  }

  final containerXml = XmlDocument.parse(
    utf8.decode(containerFile.content as List<int>),
  );

  final rootFilePath = containerXml
      .findAllElements('rootfile')
      .firstOrNull
      ?.getAttribute('full-path');

  if (rootFilePath == null) {
    throw Exception('Invalid EPUB: missing rootfile path');
  }

  // Parse OPF file
  final opfFile = archive.findFile(rootFilePath);
  if (opfFile == null) {
    throw Exception('Invalid EPUB: missing OPF file at $rootFilePath');
  }

  final opfContent = utf8.decode(opfFile.content as List<int>);
  final opfXml = XmlDocument.parse(opfContent);

  // Get base directory for resolving relative paths
  final baseDir = rootFilePath.contains('/')
      ? rootFilePath.substring(0, rootFilePath.lastIndexOf('/') + 1)
      : '';

  // Extract metadata
  String title = '';
  String author = '';

  final metadata = opfXml.findAllElements('metadata').firstOrNull;
  if (metadata != null) {
    title = metadata.findAllElements('dc:title').firstOrNull?.innerText ?? '';
    author =
        metadata.findAllElements('dc:creator').firstOrNull?.innerText ?? '';
  }

  // Build manifest map (id -> href)
  final manifest = <String, String>{};
  final mediaTypes = <String, String>{};
  for (final item in opfXml.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    final mediaType = item.getAttribute('media-type');
    if (id != null && href != null) {
      manifest[id] = href;
      if (mediaType != null) {
        mediaTypes[href] = mediaType;
      }
    }
  }

  // Get spine order (list of idrefs)
  final spineIds = <String>[];
  for (final itemRef in opfXml.findAllElements('itemref')) {
    final idref = itemRef.getAttribute('idref');
    if (idref != null) {
      spineIds.add(idref);
    }
  }

  // Try to parse TOC (NCX or NAV) for chapter labels
  final tocLabels = <String, String>{}; // href -> label
  try {
    _parseTocFromOpf(archive, opfXml, baseDir, tocLabels);
  } catch (e) {
    AnxLog.warning('Failed to parse TOC: $e');
  }

  // Extract chapter content in spine order
  final chapters = <EpubChapter>[];
  for (final idref in spineIds) {
    final href = manifest[idref];
    if (href == null) continue;

    final mediaType = mediaTypes[href] ?? '';
    // Only process XHTML content documents
    if (!mediaType.contains('html') && !mediaType.contains('xml')) {
      continue;
    }

    final fullPath = '$baseDir$href';
    final contentFile = archive.findFile(fullPath);
    if (contentFile == null) continue;

    try {
      final htmlContent =
          utf8.decode(contentFile.content as List<int>);
      final textContent = _extractTextFromHtml(htmlContent);

      if (textContent.trim().isEmpty) continue;

      final label = tocLabels[href] ??
          tocLabels[href.split('#').first] ??
          'Chapter ${chapters.length + 1}';

      chapters.add(EpubChapter(
        href: href,
        label: label,
        content: textContent.trim(),
      ));
    } catch (e) {
      AnxLog.warning('Failed to parse chapter $href: $e');
    }
  }

  return EpubBookInfo(
    title: title.isEmpty ? 'Unknown' : title,
    author: author.isEmpty ? 'Unknown' : author,
    chapters: chapters,
  );
}

void _parseTocFromOpf(
  Archive archive,
  XmlDocument opfXml,
  String baseDir,
  Map<String, String> tocLabels,
) {
  // Find NCX reference in spine
  final spine = opfXml.findAllElements('spine').firstOrNull;
  final tocId = spine?.getAttribute('toc');

  if (tocId != null) {
    // Find NCX file in manifest
    final ncxHref = opfXml
        .findAllElements('item')
        .where((el) => el.getAttribute('id') == tocId)
        .firstOrNull
        ?.getAttribute('href');

    if (ncxHref != null) {
      final ncxFile = archive.findFile('$baseDir$ncxHref');
      if (ncxFile != null) {
        final ncxContent =
            utf8.decode(ncxFile.content as List<int>);
        final ncxXml = XmlDocument.parse(ncxContent);
        _parseNcxPoints(ncxXml.findAllElements('navPoint'), tocLabels);
        return;
      }
    }
  }

  // Try NAV document (EPUB3)
  for (final item in opfXml.findAllElements('item')) {
    if (item.getAttribute('media-type') == 'application/xhtml+xml') {
      final properties = item.getAttribute('properties');
      if (properties != null && properties.contains('nav')) {
        final href = item.getAttribute('href');
        if (href != null) {
          final navFile = archive.findFile('$baseDir$href');
          if (navFile != null) {
            final navContent =
                utf8.decode(navFile.content as List<int>);
            final navXml = XmlDocument.parse(navContent);
            for (final nav in navXml.findAllElements('nav')) {
              final type = nav.getAttribute('epub:type') ??
                  nav.getAttribute('type');
              if (type == 'toc') {
                _parseNavPoints(nav.findAllElements('a'), tocLabels);
              }
            }
            return;
          }
        }
      }
    }
  }
}

void _parseNcxPoints(
  Iterable<XmlElement> navPoints,
  Map<String, String> tocLabels,
) {
  for (final point in navPoints) {
    final label = point
            .findAllElements('navLabel')
            .firstOrNull
            ?.findAllElements('text')
            .firstOrNull
            ?.innerText ??
        '';
    final src = point
            .findAllElements('content')
            .firstOrNull
            ?.getAttribute('src') ??
        '';

    if (label.isNotEmpty && src.isNotEmpty) {
      final href = src.split('#').first;
      tocLabels[href] = label;
    }

    // Recurse into nested navPoints
    _parseNcxPoints(point.findAllElements('navPoint'), tocLabels);
  }
}

void _parseNavPoints(
  Iterable<XmlElement> links,
  Map<String, String> tocLabels,
) {
  for (final link in links) {
    final href = link.getAttribute('href');
    final label = link.innerText;
    if (href != null && label.isNotEmpty) {
      tocLabels[href.split('#').first] = label.trim();
    }
  }
}

String _extractTextFromHtml(String html) {
  try {
    final doc = XmlDocument.parse(html);
    final body = doc.findAllElements('body').firstOrNull;
    if (body == null) return '';
    return _extractText(body).trim();
  } catch (_) {
    // Fallback: strip tags with regex
    return html
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

String _extractText(XmlNode node) {
  final buffer = StringBuffer();
  for (final child in node.children) {
    if (child is XmlText) {
      buffer.write(child.value);
    } else if (child is XmlElement) {
      final tag = child.name.local.toLowerCase();
      // Skip script and style
      if (tag == 'script' || tag == 'style') continue;
      // Add newlines for block elements
      if (['p', 'div', 'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote']
          .contains(tag)) {
        buffer.write('\n');
      }
      buffer.write(_extractText(child));
    }
  }
  return buffer.toString();
}
