class Product {
  final int? id;
  final int storeId;
  final String name;
  final String brand;
  final String barcodeId;
  final String batch;
  final String category;
  final int quantity;
  final DateTime? prodDate;
  final DateTime expiryDate;
  final DateTime addedDate;
  final String notes;
  final String createdBy;

  const Product({
    this.id,
    this.storeId = 1,
    required this.name,
    this.brand = '',
    this.barcodeId = '',
    this.batch = '',
    this.category = 'General',
    this.quantity = 1,
    this.prodDate,
    required this.expiryDate,
    required this.addedDate,
    this.notes = '',
    this.createdBy = '',
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

  /// Expiring between 31 and 90 days from today.
  bool get isExpiring90 => daysLeft > 30 && daysLeft <= 90;

  String get statusLabel {
    if (isExpired) return 'Expired';
    if (daysLeft == 0) return 'Expires today';
    if (daysLeft <= 30) return 'Expiring soon';
    if (daysLeft <= 90) return 'Expiring within 90 days';
    return 'Fresh';
  }

  Product copyWith({
    int? id,
    int? storeId,
    String? name,
    String? brand,
    String? barcodeId,
    String? batch,
    String? category,
    int? quantity,
    DateTime? prodDate,
    bool clearProdDate = false,
    DateTime? expiryDate,
    DateTime? addedDate,
    String? notes,
    String? createdBy,
  }) {
    return Product(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      barcodeId: barcodeId ?? this.barcodeId,
      batch: batch ?? this.batch,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      prodDate: clearProdDate ? null : (prodDate ?? this.prodDate),
      expiryDate: expiryDate ?? this.expiryDate,
      addedDate: addedDate ?? this.addedDate,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'name': name,
      'brand': brand,
      'barcodeId': barcodeId,
      'batch': batch,
      'category': category,
      'quantity': quantity,
      'prodDate': prodDate?.toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      'addedDate': addedDate.toIso8601String(),
      'notes': notes,
      'createdBy': createdBy,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final prodRaw = map['prodDate'];
    return Product(
      id: map['id'] as int?,
      storeId: map['storeId'] as int? ?? 1,
      name: map['name'] as String? ?? '',
      brand: map['brand'] as String? ?? '',
      barcodeId: map['barcodeId'] as String? ?? '',
      batch: map['batch'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      quantity: map['quantity'] as int? ?? 1,
      prodDate: prodRaw is String && prodRaw.isNotEmpty
          ? DateTime.tryParse(prodRaw)
          : null,
      expiryDate: DateTime.parse(map['expiryDate'] as String),
      addedDate: DateTime.parse(map['addedDate'] as String),
      notes: map['notes'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
    );
  }

  static const categories = [
    'General',
    'Shisha Flavours',
    'Salt Liquids',
    'Free Base Liquids',
    'Detox Products',
    'Prefilled Vape Pods',
    'Prefilled Kits',
    'Other',
  ];
}
