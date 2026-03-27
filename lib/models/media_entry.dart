class MediaItem {
  final String id;
  final String path;
  final String? thumbnailPath;

  MediaItem({required this.id, required this.path, this.thumbnailPath});

  Map<String, dynamic> toJson() => {
    'id': id, 
    'path': path, 
    'thumbnailPath': thumbnailPath
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id']?.toString() ?? '', 
    path: json['path']?.toString() ?? '', 
    thumbnailPath: json['thumbnailPath']?.toString()
  );
}

class MediaFolder {
  final String id;
  String name;
  final String type; 
  List<MediaItem> items;

  MediaFolder({required this.id, required this.name, required this.type, required this.items});

  Map<String, dynamic> toJson() => {
    'id': id, 
    'name': name, 
    'type': type, 
    'items': items.map((e) => e.toJson()).toList()
  };

  factory MediaFolder.fromJson(Map<String, dynamic> json) => MediaFolder(
    id: json['id']?.toString() ?? '', 
    name: json['name']?.toString() ?? 'Unnamed', 
    type: json['type']?.toString() ?? 'photo',
    items: (json['items'] as List?)?.map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? []
  );
}