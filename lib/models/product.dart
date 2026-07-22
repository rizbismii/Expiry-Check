class Product {
  final int? id;

  /// Stable UUID used as the Supabase primary key across devices.
  final String cloudId;
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
  final DateTime updatedAt;
  final String notes;
  final String createdBy;

  const Product({
    this.id,
    this.cloudId = '',
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
    DateTime? updatedAt,
    this.notes = '',
    this.createdBy = '',
  }) : updatedAt = updatedAt ?? addedDate;

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
    String? cloudId,
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
    DateTime? updatedAt,
    String? notes,
    String? createdBy,
  }) {
    return Product(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
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
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cloudId': cloudId,
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
      'updatedAt': updatedAt.toIso8601String(),
      'notes': notes,
      'createdBy': createdBy,
    };
  }

  /// Row payload for Supabase upsert (snake_case columns).
  Map<String, dynamic> toRemoteMap(String shopId) {
    return {
      'id': cloudId,
      'shop_id': shopId,
      'store_id': storeId,
      'name': name,
      'brand': brand,
      'barcode_id': barcodeId,
      'batch': batch,
      'category': category,
      'quantity': quantity,
      'prod_date': prodDate?.toUtc().toIso8601String(),
      'expiry_date': expiryDate.toUtc().toIso8601String(),
      'added_date': addedDate.toUtc().toIso8601String(),
      'notes': notes,
      'created_by': createdBy,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': null,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final prodRaw = map['prodDate'];
    final updatedRaw = map['updatedAt'];
    final added = DateTime.parse(map['addedDate'] as String);
    return Product(
      id: map['id'] as int?,
      cloudId: map['cloudId'] as String? ?? '',
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
      addedDate: added,
      updatedAt: updatedRaw is String && updatedRaw.isNotEmpty
          ? DateTime.parse(updatedRaw)
          : added,
      notes: map['notes'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
    );
  }

  factory Product.fromRemoteMap(Map<String, dynamic> map) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    final added = parseDt(map['added_date']) ?? DateTime.now();
    return Product(
      cloudId: map['id'] as String? ?? '',
      storeId: map['store_id'] as int? ?? 1,
      name: map['name'] as String? ?? '',
      brand: map['brand'] as String? ?? '',
      barcodeId: map['barcode_id'] as String? ?? '',
      batch: map['batch'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      quantity: map['quantity'] as int? ?? 1,
      prodDate: parseDt(map['prod_date']),
      expiryDate: parseDt(map['expiry_date']) ?? added,
      addedDate: added,
      updatedAt: parseDt(map['updated_at']) ?? added,
      notes: map['notes'] as String? ?? '',
      createdBy: map['created_by'] as String? ?? '',
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
