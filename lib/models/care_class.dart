import 'package:flutter/material.dart';

class CareClass {
  final String id;
  final String name;
  final String colorHex;
  final List<ClassDevice> devices;
  final int createdAt;
  final int updatedAt;

  const CareClass({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.devices,
    required this.createdAt,
    required this.updatedAt,
  });

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  factory CareClass.fromDatabase(String id, Object? value) {
    final data = Map<Object?, Object?>.from(value as Map);

    return CareClass(
      id: id,
      name: data['name']?.toString() ?? 'Untitled class',
      colorHex: data['colorHex']?.toString() ?? '#705FD9',
      devices: _parseDevices(data['devices']),
      createdAt: data['createdAt'] is int ? data['createdAt'] as int : 0,
      updatedAt: data['updatedAt'] is int ? data['updatedAt'] as int : 0,
    );
  }

  static List<ClassDevice> _parseDevices(Object? value) {
    if (value == null) return [];

    final data = Map<Object?, Object?>.from(value as Map);
    final devices = data.entries.map((entry) {
      final deviceData = Map<Object?, Object?>.from(entry.value as Map);
      final id = entry.key.toString();
      final name = deviceData['studentName']?.toString().trim();
      return ClassDevice(
        deviceId: id,
        //older versions saved a "Student WWWATCH-..." placeholder, treat it as no name
        studentName: name == null ||
                name.isEmpty ||
                name == 'Student ${id.toUpperCase()}'
            ? null
            : name,
      );
    }).toList();

    devices.sort((a, b) => a.deviceId.compareTo(b.deviceId));
    return devices;
  }
}

class ClassDevice {
  final String deviceId;
  final String? studentName;

  const ClassDevice({
    required this.deviceId,
    this.studentName,
  });

  //student name in this class, else the BLE id
  String get name => studentName ?? deviceId;
}
