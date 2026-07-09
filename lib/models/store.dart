class Store {
  final int id;
  final String name;

  const Store({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory Store.fromMap(Map<String, dynamic> map) => Store(
        id: map['id'] as int,
        name: map['name'] as String? ?? '',
      );
}
