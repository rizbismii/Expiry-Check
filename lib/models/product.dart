class Product {
  final int? id;
  final String name;
  final String brand;
  final String batch;
  final String category;
  final int quantity;
  final DateTime expiryDate;
  final DateTime addedDate;
  final String notes;

  const Product({
    this.id,
    required this.name,
    this.brand = '',
    this.batch = '',
    this.category = 'General',
    this.quantity = 1,
    required this.expiryDate,
    required this.addedDate,
    this.notes = '',
  });

  int get daysLeft {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final expiry =
        DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return expiry.difference(startOfToday).inDays;
  }

  bool get isExpired => daysLeft < 0;

  bool get isExpiringSoon => daysLeft >= 0 && daysLeft <= 30;

  String get statusLabel {
    if (isExpired) return 'Expired';
    if (daysLeft == 0) return 'Expires today';
    if (daysLeft <= 30) return 'Expiring soon';
    return 'Fresh';
  }

  Product copyWith({
    int? id,
    String? name,
    String? brand,
    String? batch,
    String? category,
    int? quantity,
    DateTime? expiryDate,
    DateTime? addedDate,
    String? notes,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      batch: batch ?? this.batch,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      expiryDate: expiryDate ?? this.expiryDate,
      addedDate: addedDate ?? this.addedDate,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'batch': batch,
      'category': category,
      'quantity': quantity,
      'expiryDate': expiryDate.toIso8601String(),
      'addedDate': addedDate.toIso8601String(),
      'notes': notes,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      brand: map['brand'] as String? ?? '',
      batch: map['batch'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      quantity: map['quantity'] as int? ?? 1,
      expiryDate: DateTime.parse(map['expiryDate'] as String),
      addedDate: DateTime.parse(map['addedDate'] as String),
      notes: map['notes'] as String? ?? '',
    );
  }

  static const categories = [
    'General',
    'Food & Beverage',
    'Dairy',
    'Medicine',
    'Cosmetics',
    'Cleaning',
    'Baby Care',
    'Other',
  ];
}
