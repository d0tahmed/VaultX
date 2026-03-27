class PasswordEntry {
  final String id;
  final String title;
  final String email;
  final String password;

  PasswordEntry({
    required this.id,
    required this.title,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'email': email,
    'password': password,
  };

  factory PasswordEntry.fromJson(Map<String, dynamic> json) => PasswordEntry(
    id: json['id'],
    title: json['title'],
    email: json['email'],
    password: json['password'],
  );
}

class PasswordCategory {
  final String id;
  final String name;
  List<PasswordEntry> entries;

  PasswordCategory({
    required this.id,
    required this.name,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory PasswordCategory.fromJson(Map<String, dynamic> json) => PasswordCategory(
    id: json['id'],
    name: json['name'],
    entries: (json['entries'] as List).map((e) => PasswordEntry.fromJson(e)).toList(),
  );
}