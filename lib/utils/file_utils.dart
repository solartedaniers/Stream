import 'package:flutter/material.dart';

/// Describes visual metadata for a supported file type.
class FileTypeInfo {
  /// Creates immutable file type presentation data.
  const FileTypeInfo({
    required this.icon,
    required this.color,
    required this.labelKey,
  });

  /// Material icon used to represent the file type.
  final IconData icon;

  /// Accent color used by the tile icon.
  final Color color;

  /// Localization key for the file type label.
  final String labelKey;
}

/// Provides helpers for file names, extensions, icons, and colors.
class FileUtils {
  static const String _pdfExtension = '.pdf';
  static const String _jpgExtension = '.jpg';
  static const String _jpegExtension = '.jpeg';
  static const String _pngExtension = '.png';
  static const String _docxExtension = '.docx';
  static const String _xlsxExtension = '.xlsx';
  static const String _zipExtension = '.zip';
  static const String _fallbackFileNameKey = 'unknownFileName';

  /// Returns a clean file name from a URL or local path.
  static String getFileName(String source, String fallbackFileName) {
    final Uri? parsedUri = Uri.tryParse(source);
    final String path = parsedUri?.path.isNotEmpty == true
        ? parsedUri!.path
        : source;
    final String decodedPath = Uri.decodeComponent(path);
    final List<String> parts = decodedPath
        .replaceAll('\\', '/')
        .split('/')
        .where((String part) => part.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return fallbackFileName.isEmpty ? _fallbackFileNameKey : fallbackFileName;
    }

    final String fileName = parts.last.split('?').first.trim();
    return fileName.isEmpty ? fallbackFileName : fileName;
  }

  /// Returns the lowercase file extension found in the provided source.
  static String getExtension(String source) {
    final String fileName = getFileName(source, '');
    final int extensionStart = fileName.lastIndexOf('.');
    if (extensionStart < 0 || extensionStart == fileName.length - 1) {
      return '';
    }
    return fileName.substring(extensionStart).toLowerCase();
  }

  /// Returns icon, accent color, and localization key for a source.
  static FileTypeInfo getFileTypeInfo(String source) {
    switch (getExtension(source)) {
      case _pdfExtension:
        return const FileTypeInfo(
          icon: Icons.picture_as_pdf_outlined,
          color: Color(0xFFC62828),
          labelKey: 'pdfFile',
        );
      case _jpgExtension:
      case _jpegExtension:
      case _pngExtension:
        return const FileTypeInfo(
          icon: Icons.image_outlined,
          color: Color(0xFF2E7D32),
          labelKey: 'imageFile',
        );
      case _docxExtension:
        return const FileTypeInfo(
          icon: Icons.description_outlined,
          color: Color(0xFF1565C0),
          labelKey: 'wordFile',
        );
      case _xlsxExtension:
        return const FileTypeInfo(
          icon: Icons.table_chart_outlined,
          color: Color(0xFF00897B),
          labelKey: 'spreadsheetFile',
        );
      case _zipExtension:
        return const FileTypeInfo(
          icon: Icons.folder_zip_outlined,
          color: Color(0xFFEF6C00),
          labelKey: 'zipFile',
        );
      default:
        return const FileTypeInfo(
          icon: Icons.insert_drive_file_outlined,
          color: Color(0xFF546E7A),
          labelKey: 'genericFile',
        );
    }
  }
}
