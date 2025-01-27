import 'package:flutter/material.dart';

// Creates a dropdown widget with a list of selectable items
Widget buildDropdown(List<String> items, String value, Function(String?) onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: DropdownButton<String>(
      value: value,
      isExpanded: true,
      items: items.map((item) {
        return DropdownMenuItem(value: item, child: Text(item));
      }).toList(),
      onChanged: onChanged,
    ),
  );
}
