import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/theme/app_theme.dart';

//delete and edit go in opposite corners so they're hard to mis-tap
class ClassTile extends StatelessWidget {
  const ClassTile({
    super.key,
    required this.careClass,
    required this.connectedCount,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final CareClass careClass;

  final int connectedCount;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final students = careClass.devices.length;

    return AppCard(
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onOpen,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.school_outlined, color: careClass.color, size: 26),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      careClass.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$students ${students == 1 ? 'student' : 'students'} · '
                    '$connectedCount '
                    '${connectedCount == 1 ? 'watch' : 'watches'} connected',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -8,
            left: -8,
            child: IconButton(
              tooltip: 'Delete class',
              icon: const Icon(Icons.delete_outline, size: 22),
              color: appMuted,
              onPressed: onDelete,
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              tooltip: 'Edit class',
              icon: const Icon(Icons.edit_outlined, size: 22),
              color: appMuted,
              onPressed: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}
